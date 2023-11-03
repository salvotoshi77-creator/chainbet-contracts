// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
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
contract ChainBetFactory is Owned {
    using SafeTransferLib for ERC20;
    using FunctionsRequest for FunctionsRequest.Request;
    using LibString for uint;

    event BetCreated(address indexed creator, uint indexed matchId, address indexed bet);

    ERC20 public USDC;
    address public functions_router;
    mapping(address creator => mapping(uint matchId => address bet)) public bets;
    uint public subscriptionAndGasLimit = (1537 << 128) | 300000;
    bytes32 public donID;

    string private source = ""; 

    constructor(
        address router,
        address _usdc,
        uint _subscriptionId,
        uint _gasLimit,
        bytes32 _donID,
        string memory _source
    ) Owned(msg.sender) {
        functions_router = router;
        source = _source;
        USDC = ERC20(_usdc);
        subscriptionAndGasLimit = (_subscriptionId << 128) | _gasLimit;
        donID = _donID;
    }

    function updateFunctionsParams(uint _subscriptionId, uint _gasLimit) external onlyOwner {
        subscriptionAndGasLimit = (_subscriptionId << 128) | _gasLimit;
    }

    function updateFunctionsRouter(address router) external onlyOwner {
        functions_router = router;
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
        require(bets[msg.sender][_matchId] == address(0), "Bet already exists");
        require(_wager > 0, "Wager must be greater than 0");

        // encode the api request
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(source);
        string[] memory args = new string[](1);
        args[0] = _matchId.toString();
        req.setArgs( args );
        uint betInfo = (_wager << 128) | (_matchId << 64) | (_margin << 32) | (_winner ? 1 << 31 : 0) | (_cover ? 1 << 30 : 0);
        console.log(betInfo);
        FunctionsConsumerExample bet = new FunctionsConsumerExample(
            functions_router, 
            msg.sender,
            betInfo,
            subscriptionAndGasLimit,
            donID,
            address(USDC),
            req.encodeCBOR()
        );
        bets[msg.sender][_matchId] = address(bet);
        USDC.safeTransferFrom(msg.sender, address(bet), _wager);
        emit BetCreated(msg.sender, _matchId, address(bet));
        return bet;
    }
}
