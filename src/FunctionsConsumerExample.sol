// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";
import { LibString } from "lib/solady/src/utils/LibString.sol";
import { console } from "lib/forge-std/src/console.sol";
import { ERC20 } from "lib/solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "lib/solmate/src/utils/SafeTransferLib.sol";
import { Bytes32AddressLib } from "lib/solmate/src/utils/Bytes32AddressLib.sol";
import { CCIPReceiver } from "@chainlink-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import { Client } from "@chainlink-ccip/src/v0.8/ccip/libraries/Client.sol";
import { Router } from "@chainlink-ccip/src/v0.8/ccip/Router.sol";
import { ChainBetFactory } from "./BettingFactory.sol";
/**
 * @title Chainlink Functions Betting Contract
 * @author 0xTinder
 * @notice 
 */
contract FunctionsConsumerExample is ConfirmedOwner, CCIPReceiver {
    using FunctionsRequest for FunctionsRequest.Request;
    using LibString for uint;
    using SafeTransferLib for ERC20;
    using Bytes32AddressLib for bytes32;
    using Bytes32AddressLib for address;
    // wager [255-128] | matchId [127-64] | margin [63-32] | away_win [31] | cover [30] | finished [29]
    uint public betInfo; 
    bytes32 public cover;
    bytes32 public ats;
    mapping (uint64 => bool) public allowedChains;
    // computed at constructor time           
    bytes public cbor;
    ERC20 public immutable TOKEN;
    ERC20 public immutable wNative;
    
    event CCIPMessageReceived(
        bytes32 indexed messageId, 
        address indexed sender, 
        string data, 
        address token, 
        uint amount
    );
    event CCIPPaymentSent(
        bytes32 indexed messageId, 
        uint64 indexed chainSelector, 
        address indexed to, 
        uint amount, 
        uint fee
    );
    event CCIPMessageFailed(bytes32 indexed messageId, bytes error);
    event Response(bytes32 indexed requestId, bytes response);
    event Covered(uint indexed matchId, address indexed cover, address indexed ats, uint margin, uint payout);
    event ATS(uint indexed matchId, address indexed ats, address indexed cover, uint margin, uint payout);
    event Push(uint indexed matchId, address indexed cover, address indexed ats, uint margin, uint payout);
    event Payout(uint indexed matchId, address indexed to, uint indexed amount);
    event BetTaken(uint indexed matchId, bytes32 indexed cover, bytes32 indexed ats);
    modifier onlyParticipants() {
        require(msg.sender == cover.fromLast20Bytes() || msg.sender == ats.fromLast20Bytes(), "Only participants can call this function");
        _;
    }

    constructor(
        address _ccipRouter,
        uint64  _allowedChain,
        address _player1,
        uint    _betInfo,
        address _TOKEN,
        address _wNative,
        bytes memory _cbor
    ) ConfirmedOwner(msg.sender) CCIPReceiver(_ccipRouter) {
        // pack and store matchId and margin
        betInfo = _betInfo; // 
        // player1 will never be ccip
        if (_betInfo >> 30 & 1 == 1) {
            cover = _player1.fillLast12Bytes();
        } else {
            ats = _player1.fillLast12Bytes();
        }
        allowedChains[_allowedChain] = true;
        // store the rest of the constructor params
        TOKEN = ERC20(_TOKEN);
        wNative = ERC20(_wNative);
        cbor = _cbor;
    }

    function ccipReceive(
        Client.Any2EVMMessage calldata any2EvmMessage
    ) external override onlyRouter {
        try this.processMessage(any2EvmMessage) {
            // no action needed if call succeeds
        } catch (bytes memory err) {
            emit CCIPMessageFailed(any2EvmMessage.messageId, err);
        }
    }

    function processMessage(
        Client.Any2EVMMessage calldata any2EvmMessage
    ) external {
        require(msg.sender == address(this), "only self");
        _ccipReceive(any2EvmMessage);
    }

    function _ccipReceive(
        Client.Any2EVMMessage memory any2EvmMessage
    ) internal override {
        require(allowedChains[any2EvmMessage.sourceChainSelector], "Message from disallowed chain");
        // should send true when wants to take bet, false when wants to settle
        address sender = abi.decode(any2EvmMessage.sender, (address) );
        bool _takeBet = abi.decode(any2EvmMessage.data, (bool) );
        if (_takeBet) {
            require(cover == bytes32(0) || ats == bytes32(0), "Bet already taken");
            require(sender != cover.fromLast20Bytes() && sender != ats.fromLast20Bytes(), "!player1");
            uint _betInfo = betInfo;
            require(_betInfo >> 29 & 1 == 0, "Bet already finished");
            if (cover == bytes32(0)) {
                cover = bytes32((uint(any2EvmMessage.sourceChainSelector) << 160) | uint(sender.fillLast12Bytes()));
            } else {
                ats = bytes32((uint(any2EvmMessage.sourceChainSelector) << 160) | uint(sender.fillLast12Bytes()));
            }
            uint wager = _betInfo >> 128;
            require(any2EvmMessage.destTokenAmounts[0].amount >= wager, "Not enough funds");
            require(any2EvmMessage.destTokenAmounts[0].token == address(TOKEN), "Wrong token");
            require(TOKEN.balanceOf(address(this)) >= 2 * wager, "Invalid funds");
            emit BetTaken(_betInfo >> 64 & 0xffffffffffffffff, cover, ats);
        } else {
            require(cover != bytes32(0) && ats != bytes32(0), "Bet not taken");
            require(betInfo >> 29 & 1 == 0, "Bet already finished");
            ChainBetFactory(owner()).sendFunctionRequest(cbor);
        }

        emit CCIPMessageReceived(
            any2EvmMessage.messageId, 
            sender,
            abi.decode(any2EvmMessage.data, (string) ),
            any2EvmMessage.destTokenAmounts[0].token,
            any2EvmMessage.destTokenAmounts[0].amount
        );
    }

    function withdraw() external {
        require(cover == bytes32(0) || ats == bytes32(0), "Bet already taken");
        require(msg.sender == cover.fromLast20Bytes() || msg.sender == ats.fromLast20Bytes(), "Only player can call this function");
        betInfo = betInfo | (1 << 29); // mark bet as finished
        TOKEN.transfer(msg.sender, TOKEN.balanceOf(address(this)));
    }

    function takeBet() external {
        require(cover == bytes32(0) || ats == bytes32(0), "Bet already taken");
        require(msg.sender != cover.fromLast20Bytes() && msg.sender != ats.fromLast20Bytes(), "!player1");
        uint _betInfo = betInfo;
        require(_betInfo >> 29 & 1 == 0, "Bet already finished");
        if (cover == bytes32(0)) {
            cover = msg.sender.fillLast12Bytes();
        } else {
            ats = msg.sender.fillLast12Bytes();
        }
        // transfer wager from player2 to this contract
        uint wager = _betInfo >> 128;
        TOKEN.safeTransferFrom(msg.sender, address(this), wager);

        emit BetTaken(_betInfo >> 64 & 0xffffffffffffffff, cover, ats);
    }

    function settle() external onlyParticipants returns (bytes32 requestId) {
        require(cover != bytes32(0) && ats != bytes32(0), "Bet not taken");
        require(betInfo >> 29 & 1 == 0, "Bet already finished");
        requestId = ChainBetFactory(owner()).sendFunctionRequest(cbor);
    }

    // TODO: MUST TURN INTERNAL BEFORE LAUNCH
    function processResults(uint bits) external onlyOwner {
        // wager [255-128] | matchId [127-64] | margin [63-32] | away_win [31]
        uint _betInfo = betInfo;
    
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

        // emit event
        uint matchId = _betInfo >> 64 & 0xffffffffffffffff;
        bool api_winner = (bits >> 1) & 1 == 1;
        uint api_margin = (bits >> 2) & 0xFFFF;
        bool bet_winner = (_betInfo >> 31) & 1 == 1;
        uint bet_margin = (_betInfo >> 32) & 0xffffffff;
        address _cover = cover.fromLast20Bytes();
        address _ats = ats.fromLast20Bytes();
        uint payout = TOKEN.balanceOf(address(this));
        // home team won = 0, away team won = 1
        if ((!api_winner && !bet_winner) || (api_winner && bet_winner)) {
            if (api_margin * 10 > bet_margin) {
                // bet won, money to cover
                emit Covered(matchId, _cover, _ats, api_margin, payout);
                _payout(matchId, cover, payout);
            } else if (api_margin * 10 == bet_margin) {
                // push, split money
                emit Push(matchId, _cover, _ats, api_margin, payout);
                _payout(matchId, cover, payout / 2);
                _payout(matchId, ats, payout / 2);
            } else {
                // bet lost, money to _ats
                emit ATS(matchId, _ats, _cover, api_margin, payout);
                _payout(matchId, ats, payout);
            }
            return;
        // home team won
        }
        emit ATS(matchId, _ats, _cover, api_margin, payout);
        _payout(matchId, ats, payout);

        // set betInfo to finished
        betInfo = _betInfo | (1 << 29);
    }

    function _payout(uint matchId, bytes32 to, uint amount) internal {
        // if ccip receiver, send to ccip router
        uint64 chainSelector = uint64(uint(to >> 160));
        address addr = to.fromLast20Bytes();
        if (chainSelector != 0) {
            Router router = Router(i_router);
            Client.EVMTokenAmount[] memory 
                tokenAmounts = new Client.EVMTokenAmount[](1);
            tokenAmounts[0] = Client.EVMTokenAmount({
                token: address(TOKEN),
                amount: amount
            });
            Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
                receiver: abi.encode(addr), // ABI-encoded receiver address
                data: abi.encode(""), // ABI-encoded string
                tokenAmounts: tokenAmounts, // The amount and type of token being transferred
                extraArgs: Client._argsToBytes(
                    // Additional arguments, setting gas limit and non-strict sequencing mode
                    Client.EVMExtraArgsV1({gasLimit: 200_000, strict: false})
                ),
                // Set the feeToken to a feeTokenAddress, indicating specific asset will be used for fees
                feeToken: address(wNative)
            });
            uint fee = router.getFee(chainSelector, message);
            wNative.safeTransferFrom(owner(), address(this), fee);
            wNative.approve(address(router), fee);
            bytes32 messageId = router.ccipSend(
                chainSelector,
                message
            );
            emit CCIPPaymentSent(messageId, chainSelector, addr, amount, fee);
        } else {
            // else pay normally
            TOKEN.transfer(addr, amount);
        }
        emit Payout(matchId, addr, amount);
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
}
