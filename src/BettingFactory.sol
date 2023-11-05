// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {FunctionsClient, IFunctionsRouter} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";
import { console } from "lib/forge-std/src/console.sol";
import { Owned } from "lib/solmate/src/auth/Owned.sol";
import { ERC20 } from "lib/solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "lib/solmate/src/utils/SafeTransferLib.sol";
import { FunctionsConsumerExample } from "./FunctionsConsumerExample.sol";
import { LibString } from "lib/solady/src/utils/LibString.sol";
/**
 * @title Chainlink Functions Betting Contract
 * @author 0xTinder
 * @notice 
 */
contract ChainBetFactory is Owned, FunctionsClient {
    using SafeTransferLib for ERC20;
    using FunctionsRequest for FunctionsRequest.Request;
    using LibString for uint;

    error UnexpectedRequestID(bytes32 requestId);

    event BetCreated(address indexed creator, uint indexed matchId, address indexed bet);
    event Response(bytes32 indexed requestId, bytes response);

    ERC20 public TOKEN;
    ERC20 public wNative;
    address public ccip_router;
    uint public subscriptionAndGasLimit = (1537 << 128) | 300000;
    bytes32 public donID;
    uint64 public allowedChain;
    string private source = ""; 
    mapping(address bet => bool) public isBet;
    mapping(bytes32 reqId => address bet) public reqToBet;
    constructor(
        address _ccipRouter,
        address _functions_router,
        uint64  _allowedChain,
        address token,
        address _wNative,
        uint _subscriptionId,
        uint _gasLimit,
        bytes32 _donID,
        string memory _source
    ) Owned(msg.sender) FunctionsClient(_functions_router) {
        ccip_router = _ccipRouter;
        source = _source;
        TOKEN = ERC20(token);
        wNative = ERC20(_wNative);
        subscriptionAndGasLimit = (_subscriptionId << 128) | _gasLimit;
        donID = _donID;
        allowedChain = _allowedChain;
    }

    function updateFunctionsParams(uint _subscriptionId, uint _gasLimit) external onlyOwner {
        subscriptionAndGasLimit = (_subscriptionId << 128) | _gasLimit;
    }

    function updateDonID(bytes32 _donID) external onlyOwner {
        donID = _donID;
    }

    function createBet(
        uint _matchId, 
        uint _wager, 
        uint _margin, 
        bool _cover, 
        bool _winner
    ) external returns (FunctionsConsumerExample betAddr) {
        require(_wager > 0, "Wager must be greater than 0");
        // encode the api request
        uint betInfo = (_wager << 128) | (_matchId << 64) | (_margin << 32) | (_winner ? 1 << 31 : 0) | (_cover ? 1 << 30 : 0);
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(source);
        string[] memory args = new string[](1);
        args[0] = _matchId.toString();
        req.setArgs( args );
        bytes memory cbor = req.encodeCBOR();
        FunctionsConsumerExample bet = new FunctionsConsumerExample(
            ccip_router,
            allowedChain,
            msg.sender,
            betInfo,
            address(TOKEN),
            address(wNative),
            cbor
        );
        
        isBet[address(bet)] = true;

        wNative.approve(address(bet), type(uint).max);
        TOKEN.safeTransferFrom(msg.sender, address(bet), _wager);
        emit BetCreated(msg.sender, _matchId, address(bet));
        return bet;
    }

    function sendFunctionRequest(bytes memory cbor) external returns (bytes32) {
        uint subAndGL = subscriptionAndGasLimit;
        require(isBet[msg.sender], "Not a bet");
        bytes32 s_lastRequestId = _sendRequest(
            cbor,
            uint64(subAndGL >> 128),
            uint32(subAndGL & 0xffffffffffffffffffffffffffffffff),
            donID
        );
        reqToBet[s_lastRequestId] = msg.sender;
        return s_lastRequestId;
    }

        /**
     * @notice Store latest result/error
     * @param requestId The request ID, returned by sendRequest()
     * @param response Aggregated response from the user code
     * @param err Aggregated error from the user code or from the execution pipeline
     * Either response or error parameter will be set, but never both
     */
    function fulfillRequest(
        bytes32 requestId,
        bytes memory response,
        bytes memory err
    ) internal override {
        address bet = reqToBet[requestId];
        if (bet == address(0)) {
            revert UnexpectedRequestID(requestId);
        }
        emit Response(requestId, response);
        
        FunctionsConsumerExample(bet).processResults(uint(bytes32(response)));
    }
}
