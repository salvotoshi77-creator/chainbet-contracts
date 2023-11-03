// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";
import { LibString } from "lib/solady/src/utils/LibString.sol";
import { console } from "lib/forge-std/src/console.sol";
import { ERC20 } from "lib/solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "lib/solmate/src/utils/SafeTransferLib.sol";
/**
 * @title Chainlink Functions Betting Contract
 * @author 0xTinder
 * @notice 
 */
contract FunctionsConsumerExample is FunctionsClient, ConfirmedOwner {
    using FunctionsRequest for FunctionsRequest.Request;
    using LibString for uint;
    using SafeTransferLib for ERC20;
    // wager [255-128] | matchId [127-64] | margin [63-32] | away_win [31] | cover [30] | finished [29]
    uint public betInfo; 
    address public cover;
    address public ats;

    // computed at constructor time           
    bytes public cbor;
    bytes32 public immutable donID;
    uint64 public immutable subscriptionId;
    uint32 public immutable gasLimit;
    ERC20 public immutable USDC;


    // set by fulfillRequest callback, probably not needed to store
    bytes32 public s_lastRequestId;

    error UnexpectedRequestID(bytes32 requestId);
    event Response(bytes32 indexed requestId, bytes response);
    event Covered(uint indexed matchId, address indexed cover, address indexed ats, uint margin, uint payout);
    event ATS(uint indexed matchId, address indexed ats, address indexed cover, uint margin, uint payout);
    event Push(uint indexed matchId, address indexed cover, address indexed ats, uint margin, uint payout);
    event Payout(uint indexed matchId, address indexed to, uint indexed amount);
    event BetTaken(uint indexed matchId, address indexed cover, address indexed ats);
    modifier onlyParticipants() {
        require(msg.sender == cover || msg.sender == ats, "Only participants can call this function");
        _;
    }

    constructor(
        address _router,
        address _player1,
        uint    _betInfo,
        uint    _subscriptionAndGasLimit,
        bytes32 _donID,
        address _USDC,
        bytes memory _cbor
    ) FunctionsClient(_router) ConfirmedOwner(msg.sender) {
        // pack and store matchId and margin
        betInfo = _betInfo; // 
        if (_betInfo >> 30 & 1 == 1) {
            cover = _player1;
        } else {
            ats = _player1;
        }
        // store the rest of the constructor params
        subscriptionId = uint64(_subscriptionAndGasLimit >> 128);
        gasLimit = uint32(_subscriptionAndGasLimit & 0xffffffffffffffffffffffffffffffff);
        donID = _donID;
        USDC = ERC20(_USDC);
        cbor = _cbor;
    }


    function takeBet() external {
        require(cover == address(0) || ats == address(0), "Bet already taken");
        require(msg.sender != cover && msg.sender != ats, "!player1");
        uint _betInfo = betInfo;
        require(_betInfo >> 29 & 1 == 0, "Bet already finished");
        if (cover == address(0)) {
            cover = msg.sender;
        } else {
            ats = msg.sender;
        }
        // transfer wager from player2 to this contract
        uint wager = _betInfo >> 128;
        USDC.safeTransferFrom(msg.sender, address(this), wager);

        emit BetTaken(_betInfo >> 64 & 0xffffffffffffffff, cover, ats);
    }

    function settle() external onlyParticipants returns (bytes32 requestId) {
        require(cover != address(0) && ats != address(0), "Bet not taken");
        require(betInfo >> 29 & 1 == 0, "Bet already finished");
        s_lastRequestId = _sendRequest(
            cbor,
            subscriptionId,
            gasLimit,
            donID
        );
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
        if (s_lastRequestId != requestId) {
            revert UnexpectedRequestID(requestId);
        }
        emit Response(requestId, response);
        
        // wager [255-128] | matchId [127-64] | margin [63-32] | away_win [31]
        uint _betInfo = betInfo;
        uint bits = uint(bytes32(response));
    
        // (bool finished, api_winner, api_margin, uint32 api_game_id) = _parseResponse(response);
        // check if finished and if the game id matches
        // bool finished = bits & 1 == 1;
        // uint bet_game_id = (_betInfo >> 64) & 0xffffffffffffffff;
        // uint api_game_id = bits >> 18 & 0xffffffffffffffff;
        // if (!finished || bet_game_id  != api_game_id) {
        //     return;
        // }
        if (!(bits & 1 == 1) || ((_betInfo >> 64) & 0xffffffffffffffff) != (bits >> (18 & 0xffffffffffffffff))) {
            return;
        }
        // bool api_winner = (bits >> 1) & 1 == 1;
        // uint api_margin = (bits >> 2) & 0xFFFF;
        // bool bet_winner = (_betInfo >> 31) & 1 == 1;
        // uint bet_margin = (_betInfo >> 32) & 0xffffffff;
        // external transfers here
        _processResults(bits, _betInfo);

        // set betInfo to finished
        betInfo = _betInfo | (1 << 29);
        // emit event
    }

    // TODO: MUST TURN INTERNAL BEFORE LAUNCH
    function _processResults(uint _bits, uint _betInfo) public {
        uint matchId = _betInfo >> 64 & 0xffffffffffffffff;
        bool api_winner = (_bits >> 1) & 1 == 1;
        uint api_margin = (_bits >> 2) & 0xFFFF;
        bool bet_winner = (_betInfo >> 31) & 1 == 1;
        uint bet_margin = (_betInfo >> 32) & 0xffffffff;
        uint payout = USDC.balanceOf(address(this));
        // home team won = 0, away team won = 1
        if ((!api_winner && !bet_winner) || (api_winner && bet_winner)) {
            if (api_margin * 10 > bet_margin) {
                // bet won, money to cover
                USDC.transfer(cover, payout);

                emit Covered(matchId, cover, ats, api_margin, payout);
                emit Payout(matchId, cover, payout);
            } else if (api_margin * 2 == bet_margin) {
                // push, split money
                USDC.transfer(cover, payout / 2);
                USDC.transfer(ats, payout / 2);

                emit Push(matchId, cover, ats, api_margin, payout);
                emit Payout(matchId, cover, payout / 2);
                emit Payout(matchId, ats, payout / 2);
            } else {
                // bet lost, money to ats
                USDC.transfer(ats, payout);

                emit ATS(matchId, ats, cover, api_margin, payout);
                emit Payout(matchId, ats, payout);
            }
            return;
        // home team won
        }
        USDC.transfer(ats, payout);
        emit ATS(matchId, ats, cover, api_margin, payout);
        emit Payout(matchId, ats, payout);
    }

    // hooray all of the chainlink function stuff works
    // now the easy part
    function _parseResponse(bytes memory input) internal pure returns (
        bool finished,
        bool away_win,
        uint16 margin,
        uint32 game_id
    ) {
        uint bits = uint(bytes32(input));
        finished = bits & 1 == 1;
        away_win = (bits >> 1) & 1 == 1;
        margin = uint16(bits >> 2);
        game_id = uint32(bits >> 18);
    }
    // wager [255-128] | matchId [127-64] | margin [63-32] | away_win [31] | cover [30] | finished [29]
    // uint public betInfo; 
    function getBetInfo() external view returns (
        uint wager,
        uint match_id,
        uint margin,
        bool winner,
        bool _cover,
        bool finished
    ) {
        wager = betInfo >> 128;
        match_id = (betInfo >> 64) & 0xffffffffffffffff;
        margin = (betInfo >> 32) & 0xffffffff;
        winner = (betInfo >> 31) & 1 == 1;
        _cover = (betInfo >> 30) & 1 == 1;
        finished = (betInfo >> 29) & 1 == 1;
    }

        // /**
    //  * @notice Send a simple request
    //  * @param source JavaScript source code
    //  * @param encryptedSecretsUrls Encrypted URLs where to fetch user secrets
    //  * @param donHostedSecretsSlotID Don hosted secrets slotId
    //  * @param donHostedSecretsVersion Don hosted secrets version
    //  * @param args List of arguments accessible from within the source code
    //  * @param bytesArgs Array of bytes arguments, represented as hex strings
    //  * @param subscriptionId Billing ID
    //  */
    // function sendRequest(
    //     string memory source,
    //     bytes memory encryptedSecretsUrls,
    //     uint8 donHostedSecretsSlotID,
    //     uint64 donHostedSecretsVersion,
    //     string[] memory args,
    //     bytes[] memory bytesArgs,
    //     uint64 subscriptionId,
    //     uint32 gasLimit,
    //     bytes32 donID
    // ) external onlyOwner returns (bytes32 requestId) {
    //     // if (encryptedSecretsUrls.length > 0)
    //     //     req.addSecretsReference(encryptedSecretsUrls);
    //     // else if (donHostedSecretsVersion > 0) {
    //     //     req.addDONHostedSecrets(
    //     //         donHostedSecretsSlotID,
    //     //         donHostedSecretsVersion
    //     //     );
    //     // }
    //     // if (bytesArgs.length > 0) req.setBytesArgs(bytesArgs);
    //     s_lastRequestId = _sendRequest(
    //         req.encodeCBOR(),
    //         subscriptionId,
    //         gasLimit,
    //         donID
    //     );
    //     return s_lastRequestId;
    // }

    // /**
    //  * @notice Send a pre-encoded CBOR request
    //  * @param request CBOR-encoded request data
    //  * @param subscriptionId Billing ID
    //  * @param gasLimit The maximum amount of gas the request can consume
    //  * @param donID ID of the job to be invoked
    //  * @return requestId The ID of the sent request
    //  */
    // function sendRequestCBOR(
    //     bytes memory request,
    //     uint64 subscriptionId,
    //     uint32 gasLimit,
    //     bytes32 donID
    // ) external onlyOwner returns (bytes32 requestId) {
    //     s_lastRequestId = _sendRequest(
    //         request,
    //         subscriptionId,
    //         gasLimit,
    //         donID
    //     );
    //     return s_lastRequestId;
    // }
}

interface IFCE {
    function s_lastResponse() external view returns (bytes memory);
}
