// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.21 <0.9.0;

import { PRBTest } from "@prb/test/PRBTest.sol";
import { console } from "forge-std/console.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { StringStorage } from "../src/StringStorage.sol";
import { FunctionsConsumerExample } from "../src/FunctionsConsumerExample.sol";
import { ChainBetFactory } from "../src/BettingFactory.sol";
import { ERC20 } from "lib/solmate/src/tokens/ERC20.sol";
import { Bytes32AddressLib } from "lib/solmate/src/utils/Bytes32AddressLib.sol";

contract Mock20 is ERC20 {
    constructor() ERC20("Test", "TST", 6) {}
}

/// @dev If this is your first time with Forge, read this tutorial in the Foundry Book:
/// https://book.getfoundry.sh/forge/writing-tests
contract Test is PRBTest, StdCheats {
    using Bytes32AddressLib for bytes32;
    FunctionsConsumerExample internal foo;
    ChainBetFactory internal factory;
    ERC20 internal USDC;
    address alice = address(15);
    address bob = address(14);
    /// @dev A function invoked before each test case is run.
    function setUp() public virtual {
        vm.createSelectFork("sepolia");
        // Instantiate the contract-under-test.
        address sep_ccip_router = 0xD0daae2231E9CB96b94C8512223533293C3693Bf;
        address sep_functions_router = 0xb83E47C2bC239B3bf370bc41e1459A34b41238D0;
        address sep_ccip_token = 0xFd57b4ddBf88a4e07fF4e34C487b99af2Fe82a05;
        address weth = 0x097D90c9d3E0B50Ca60e1ae45F6A81010f9FB534;
        uint sep_subscriptionId = 1537;
        bytes32 sep_donID = bytes32("fun-ethereum-sepolia-1");
        uint64 fuji_chain_selector = 14767482510784806043;

        USDC = new Mock20();
        factory = new ChainBetFactory(
            sep_ccip_router,
            sep_functions_router,
            fuji_chain_selector,
            sep_ccip_token,
            weth,
            sep_subscriptionId,
            1000000,
            sep_donID,
            source
        );
        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(address(factory), "factory");
        vm.label(address(USDC), "USDC");
    }

    function test_stringStorage() internal {
        StringStorage str = new StringStorage(source);
        str.value();
    }

    function test_demo() external {
        // FunctionsConsumerExample con = FunctionsConsumerExample(0xa14DfbEcEA91df1f366f8ABfda621006Eb07b0FC);
        FunctionsConsumerExample con = FunctionsConsumerExample((0x184716643002Ef8ccf61901a6025656d94799459));
        startHoax(0x465d1CfE1d94D427EdfE93E2010284d1eCb8839d, 0x465d1CfE1d94D427EdfE93E2010284d1eCb8839d);
        // con.wNative();
        ERC20(con.TOKEN()).balanceOf(address(0x465d1CfE1d94D427EdfE93E2010284d1eCb8839d));
        con.getBetInfo();
        con.takeBet();
        // console.log(margin, winner, _cover, finished);
        // con._processResults(2007236682, con.betInfo());
        // assertEq(gameState(7657, false, 17, 35), 0);
    }

    function gameState(uint id, bool finished, uint home, uint away) internal returns (uint state) {
        state |= finished ? 1 : 0;
        state |= home > away ? 0 : 1 << 1;
        if (home > away) {
            state |= (home - away) << 2;
        } else {
            state |= (away - home) << 2;
        }
        state |= id << 18;
    }

    function test_sanitygameState() external {
        assertEq(gameState(7657, true, 17, 31), 2005139515);
    }

    function test_home_cover_win(uint8 home, uint8 away) external {
        vm.assume(home > away);
        vm.assume(home - away > 7);
        uint wager = 10e6;
        // uint matchId = 7649;
        uint margin = 7;
        bool cover = true;
        bool winner = false; // home team

        // bet 10 dollars the home team covers 7 points
        deal(address(USDC), alice, wager);
        startHoax(alice, alice);
        USDC.approve(address(factory), wager);
        FunctionsConsumerExample bet = factory.createBet(
            0,   // match id
            wager,   // 10 USDC wager
            margin,      // 7 point margin
            cover,      // cover
            winner       // home team
        );
        vm.stopPrank();

        deal(address(USDC), bob, wager);
        startHoax(bob, bob);
        USDC.approve(address(bet), wager);
        bet.takeBet();

        // final score home team: 14, away team: 3
        // home team covers
        // bet._processResults(gameState(0, true, home, away), bet.betInfo());

        assertEq(USDC.balanceOf(address(bet)), 0);
        assertEq(USDC.balanceOf(alice), wager * 2);
        assertEq(USDC.balanceOf(bob), 0);
    }
    function test_home_cover_loss(uint8 home, uint8 away) external {
        vm.assume(home > away);
        vm.assume(home - away < 7);
        uint wager = 10e6;
        // uint matchId = 7649;
        uint margin = 7;
        bool cover = true;
        bool winner = false; // home team

        // bet 10 dollars the home team covers 7 points
        deal(address(USDC), alice, wager);
        startHoax(alice, alice);
        USDC.approve(address(factory), wager);
        FunctionsConsumerExample bet = factory.createBet(
            0,   // match id
            wager,   // 10 USDC wager
            margin,      // 7 point margin
            cover,      // cover
            winner       // home team
        );
        vm.stopPrank();

        deal(address(USDC), bob, wager);
        startHoax(bob, bob);
        USDC.approve(address(bet), wager);
        bet.takeBet();

        // final score home team: 14, away team: 3
        // home team covers
        // bet._processResults(gameState(0, true, home, away), bet.betInfo());

        assertEq(USDC.balanceOf(address(bet)), 0);
        assertEq(USDC.balanceOf(bob), wager * 2);
        assertEq(USDC.balanceOf(alice), 0);
    }
    function test_home_cover_push(uint8 home) external {
        vm.assume(home >= 7);
        uint away = home - 7;
        uint wager = 10e6;
        // uint matchId = 7649;
        uint margin = 7;
        bool cover = true;
        bool winner = false; // home team

        // bet 10 dollars the home team covers 7 points
        deal(address(USDC), alice, wager);
        startHoax(alice, alice);
        USDC.approve(address(factory), wager);
        FunctionsConsumerExample bet = factory.createBet(
            0,   // match id
            wager,   // 10 USDC wager
            margin,      // 7 point margin
            cover,      // cover
            winner       // home team
        );
        vm.stopPrank();

        deal(address(USDC), bob, wager);
        startHoax(bob, bob);
        USDC.approve(address(bet), wager);
        bet.takeBet();

        // final score home team: 14, away team: 3
        // home team covers
        // bet._processResults(gameState(0, true, home, away), bet.betInfo());

        assertEq(USDC.balanceOf(address(bet)), 0);
        assertEq(USDC.balanceOf(bob), wager);
        assertEq(USDC.balanceOf(alice), wager);
    }
    function test_away_cover_win(uint8 home, uint8 away) external {
        vm.assume(home < away);
        vm.assume(away - home > 7);
        uint wager = 10e6;
        // uint matchId = 7649;
        uint margin = 7;
        bool cover = true;
        bool winner = true; // away team

        // bet 10 dollars the away team covers 7 points
        deal(address(USDC), alice, wager);
        startHoax(alice, alice);
        USDC.approve(address(factory), wager);
        FunctionsConsumerExample bet = factory.createBet(
            0,   // match id
            wager,   // 10 USDC wager
            margin,      // 7 point margin
            cover,      // cover
            winner       // away team
        );
        vm.stopPrank();

        deal(address(USDC), bob, wager);
        startHoax(bob, bob);
        USDC.approve(address(bet), wager);
        bet.takeBet();

        // final score home team: 14, away team: 3
        // home team covers
        // bet._processResults(gameState(0, true, home, away), bet.betInfo());

        assertEq(USDC.balanceOf(address(bet)), 0);
        assertEq(USDC.balanceOf(alice), wager * 2);
        assertEq(USDC.balanceOf(bob), 0);
    }
    function test_away_cover_loss(uint8 home, uint8 away) external {
        vm.assume(home < away);
        vm.assume(away - home < 7);
        uint wager = 10e6;
        // uint matchId = 7649;
        uint margin = 7;
        bool cover = true;
        bool winner = true; // away team

        // bet 10 dollars the away team covers 7 points
        deal(address(USDC), alice, wager);
        startHoax(alice, alice);
        USDC.approve(address(factory), wager);
        FunctionsConsumerExample bet = factory.createBet(
            0,   // match id
            wager,   // 10 USDC wager
            margin,      // 7 point margin
            cover,      // cover
            winner       // away team
        );
        vm.stopPrank();

        deal(address(USDC), bob, wager);
        startHoax(bob, bob);
        USDC.approve(address(bet), wager);
        bet.takeBet();

        // bet._processResults(gameState(0, true, home, away), bet.betInfo());

        assertEq(USDC.balanceOf(address(bet)), 0);
        assertEq(USDC.balanceOf(bob), wager * 2);
        assertEq(USDC.balanceOf(alice), 0);
    }
    function test_away_cover_push(uint8 away) external {
        vm.assume(away >= 7);
        uint home = away - 7;
        uint wager = 10e6;
        // uint matchId = 7649;
        uint margin = 7;
        bool cover = true;
        bool winner = true; // away team

        deal(address(USDC), alice, wager);
        startHoax(alice, alice);
        USDC.approve(address(factory), wager);
        FunctionsConsumerExample bet = factory.createBet(
            0,   // match id
            wager,   // 10 USDC wager
            margin,      // 7 point margin
            cover,      // cover
            winner       // away team
        );
        vm.stopPrank();

        deal(address(USDC), bob, wager);
        startHoax(bob, bob);
        USDC.approve(address(bet), wager);
        bet.takeBet();

        // bet._processResults(gameState(0, true, home, away), bet.betInfo());

        assertEq(USDC.balanceOf(address(bet)), 0);
        assertEq(USDC.balanceOf(bob), wager);
        assertEq(USDC.balanceOf(alice), wager);
    }
    function test_home_ats_win(uint8 home, uint8 away) external {
        vm.assume(home != away);
        if (home > away) {
            vm.assume(home - away < 7);
        }
        uint wager = 10e6;
        // uint matchId = 7649;
        uint margin = 7;
        bool cover = false;
        bool winner = false; // home team

        // bet 10 dollars the home team covers 7 points
        deal(address(USDC), alice, wager);
        startHoax(alice, alice);
        USDC.approve(address(factory), wager);
        FunctionsConsumerExample bet = factory.createBet(
            0,   // match id
            wager,   // 10 USDC wager
            margin,      // 7 point margin
            cover,      // cover
            winner       // home team
        );
        vm.stopPrank();

        deal(address(USDC), bob, wager);
        startHoax(bob, bob);
        USDC.approve(address(bet), wager);
        bet.takeBet();

        // final score home team: 14, away team: 3
        // home team covers
        // bet._processResults(gameState(0, true, home, away), bet.betInfo());

        assertEq(USDC.balanceOf(address(bet)), 0);
        assertEq(USDC.balanceOf(alice), wager * 2);
        assertEq(USDC.balanceOf(bob), 0);
    }
    function test_home_ats_loss(uint8 home, uint8 away) external {
        vm.assume(home > away);
        vm.assume(home - away > 7);
        uint wager = 10e6;
        // uint matchId = 7649;
        uint margin = 7;
        bool cover = false;
        bool winner = false; // home team

        // bet 10 dollars the home team covers 7 points
        deal(address(USDC), alice, wager);
        startHoax(alice, alice);
        USDC.approve(address(factory), wager);
        FunctionsConsumerExample bet = factory.createBet(
            0,   // match id
            wager,   // 10 USDC wager
            margin,      // 7 point margin
            cover,      // cover
            winner       // home team
        );
        vm.stopPrank();

        deal(address(USDC), bob, wager);
        startHoax(bob, bob);
        USDC.approve(address(bet), wager);
        bet.takeBet();

        // final score home team: 14, away team: 3
        // home team covers
        // bet._processResults(gameState(0, true, home, away), bet.betInfo());

        assertEq(USDC.balanceOf(address(bet)), 0);
        assertEq(USDC.balanceOf(bob), wager * 2);
        assertEq(USDC.balanceOf(alice), 0);
    }
    function test_home_ats_push(uint8 home) external {
        vm.assume(home >= 7);
        uint away = home - 7;
        uint wager = 10e6;
        // uint matchId = 7649;
        uint margin = 7;
        bool cover = false;
        bool winner = false; // home team

        // bet 10 dollars the home team covers 7 points
        deal(address(USDC), alice, wager);
        startHoax(alice, alice);
        USDC.approve(address(factory), wager);
        FunctionsConsumerExample bet = factory.createBet(
            0,   // match id
            wager,   // 10 USDC wager
            margin,      // 7 point margin
            cover,      // cover
            winner       // home team
        );
        vm.stopPrank();

        deal(address(USDC), bob, wager);
        startHoax(bob, bob);
        USDC.approve(address(bet), wager);
        bet.takeBet();

        // final score home team: 14, away team: 3
        // home team covers
        // bet._processResults(gameState(0, true, home, away), bet.betInfo());

        assertEq(USDC.balanceOf(address(bet)), 0);
        assertEq(USDC.balanceOf(bob), wager);
        assertEq(USDC.balanceOf(alice), wager);
    }
    function test_away_ats_win(uint8 home, uint8 away) external {
        vm.assume(home != away);
        if (home < away) {
            vm.assume(away - home < 7);
        }
        uint wager = 10e6;
        // uint matchId = 7649;
        uint margin = 7;
        bool cover = false;
        bool winner = true; // home team

        // bet 10 dollars the home team covers 7 points
        deal(address(USDC), alice, wager);
        startHoax(alice, alice);
        USDC.approve(address(factory), wager);
        FunctionsConsumerExample bet = factory.createBet(
            0,   // match id
            wager,   // 10 USDC wager
            margin,      // 7 point margin
            cover,      // cover
            winner       // home team
        );
        vm.stopPrank();

        deal(address(USDC), bob, wager);
        startHoax(bob, bob);
        USDC.approve(address(bet), wager);
        bet.takeBet();

        // final score home team: 14, away team: 3
        // home team covers
        // bet._processResults(gameState(0, true, home, away), bet.betInfo());

        assertEq(USDC.balanceOf(address(bet)), 0);
        assertEq(USDC.balanceOf(alice), wager * 2);
        assertEq(USDC.balanceOf(bob), 0);
    }
    function test_away_ats_loss(uint8 home, uint8 away) external {
        vm.assume(away > home);
        vm.assume(away - home > 7);
        uint wager = 10e6;
        // uint matchId = 7649;
        uint margin = 7;
        bool cover = false;
        bool winner = true; // home team

        // bet 10 dollars the home team covers 7 points
        deal(address(USDC), alice, wager);
        startHoax(alice, alice);
        USDC.approve(address(factory), wager);
        FunctionsConsumerExample bet = factory.createBet(
            0,   // match id
            wager,   // 10 USDC wager
            margin,      // 7 point margin
            cover,      // cover
            winner       // home team
        );
        vm.stopPrank();

        deal(address(USDC), bob, wager);
        startHoax(bob, bob);
        USDC.approve(address(bet), wager);
        bet.takeBet();

        // final score home team: 14, away team: 3
        // home team covers
        // bet._processResults(gameState(0, true, home, away), bet.betInfo());

        assertEq(USDC.balanceOf(address(bet)), 0);
        assertEq(USDC.balanceOf(bob), wager * 2);
        assertEq(USDC.balanceOf(alice), 0);
    }
    function test_away_ats_push(uint8 away) external {
        vm.assume(away >= 7);
        uint home = away - 7;
        uint wager = 10e6;
        // uint matchId = 7649;
        uint margin = 7;
        bool cover = false;
        bool winner = true; // home team

        // bet 10 dollars the home team covers 7 points
        deal(address(USDC), alice, wager);
        startHoax(alice, alice);
        USDC.approve(address(factory), wager);
        FunctionsConsumerExample bet = factory.createBet(
            0,   // match id
            wager,   // 10 USDC wager
            margin,      // 7 point margin
            cover,      // cover
            winner       // home team
        );
        vm.stopPrank();

        deal(address(USDC), bob, wager);
        startHoax(bob, bob);
        USDC.approve(address(bet), wager);
        bet.takeBet();

        // final score home team: 14, away team: 3
        // home team covers
        // bet._processResults(gameState(0, true, home, away), bet.betInfo());

        assertEq(USDC.balanceOf(address(bet)), 0);
        assertEq(USDC.balanceOf(bob), wager);
        assertEq(USDC.balanceOf(alice), wager);
    }
    function test_zero_margin(uint home, uint away) external {
        uint wager = 10e6;
        // uint matchId = 7649;
        uint margin = 0;
        bool cover = true;
        bool winner = true; // away team

        // bet 10 dollars the home team covers 7 points
        deal(address(USDC), alice, wager);
        startHoax(alice, alice);
        USDC.approve(address(factory), wager);
        FunctionsConsumerExample bet = factory.createBet(
            0,   // match id
            wager,   // 10 USDC wager
            margin,      // 7 point margin
            cover,      // cover
            winner       // home team
        );
        vm.stopPrank();

        deal(address(USDC), bob, wager);
        startHoax(bob, bob);
        USDC.approve(address(bet), wager);
        bet.takeBet();

        // final score home team: 14, away team: 3
        // home team covers
        // bet._processResults(gameState(0, true, home, away), bet.betInfo());

        assertEq(USDC.balanceOf(address(bet)), 0);
        assertEq(USDC.balanceOf(bob), wager);
        assertEq(USDC.balanceOf(alice), wager);
    }
    function test_matchbet(bool cover) external {
        uint wager = 10e6;
        uint matchId = 7649;
        uint margin = 7;
        bool winner = false;

        // bet 10 dollars the home team covers 7 points

        deal(address(USDC), alice, wager);
        startHoax(alice, alice);
        USDC.approve(address(factory), wager);
        FunctionsConsumerExample bet = factory.createBet(
            matchId,   // match id
            wager,   // 10 USDC wager
            margin,      // 7 point margin
            cover,      // cover
            winner       // home team
        );
        vm.stopPrank();

        deal(address(USDC), bob, wager);
        startHoax(bob, bob);
        USDC.approve(address(bet), wager);
        bet.takeBet();

        assertEq(USDC.balanceOf(address(bet)), wager * 2);
        if (cover) {
            assertEq(bet.cover().fromLast20Bytes(), alice);
            assertEq(bet.ats().fromLast20Bytes(), bob);
        } else {
            assertEq(bet.cover().fromLast20Bytes(), bob);
            assertEq(bet.ats().fromLast20Bytes(), alice);
        }

        vm.expectRevert("Bet already taken");
        bet.takeBet();

    }

    function test_createBet(uint128 wager, uint64 matchId, uint32 margin, bool cover, bool winner) external {
        deal(address(USDC), alice, wager);
        startHoax(alice, alice);
        USDC.approve(address(factory), wager);
        bool exit = false;
        if (wager == 0) {
            vm.expectRevert("Wager must be greater than 0");
            exit = true;
        }
        FunctionsConsumerExample bet = factory.createBet(
            matchId,   // match id
            wager,   // 10 USDC wager
            margin,      // 7 point margin
            cover,      // cover
            winner       // home team
        );
        if (exit) return;

        (uint _wager, uint _matchId, uint _margin, bool _winner, bool _cover, bool _finished) = bet.getBetInfo();
        // assertions
        assertEq(_wager, wager);
        assertEq(_matchId, matchId);
        assertEq(_margin, margin);
        assertEq(_winner, winner);
        assertEq(_cover, cover);
        assertEq(_finished, false);
        if (cover) {
            assertEq(bet.cover().fromLast20Bytes(), alice);
            assertEq(bet.ats().fromLast20Bytes(), address(0));
        } else {
            assertEq(bet.cover().fromLast20Bytes(), address(0));
            assertEq(bet.ats().fromLast20Bytes(), alice);
        }
        assertEq(USDC.balanceOf(alice), 0);
        assertEq(USDC.balanceOf(address(bet)), wager);
    }

    /// @dev Basic test. Run it with `forge test -vvv` to see the console log.
    function test_ParseAPIResponse() external {
        bool finished;
        bool away_win;
        uint16 margin;
        uint32 game_id;
        // (finished, away_win, margin, game_id) = foo.parseResponse(input);
        assertEq(finished, true);
        assertEq(away_win, true);
        assertEq(margin, 14);
        assertEq(game_id, 7649);
    }

    // /// @dev Fuzz test that provides random values for an unsigned integer, but which rejects zero as an input.
    // /// If you need more sophisticated input validation, you should use the `bound` utility instead.
    // /// See https://twitter.com/PaulRBerg/status/1622558791685242880
    // function testFuzz_Example(uint256 x) external {
    //     vm.assume(x != 0); // or x = bound(x, 1, 100)
    //     assertEq(foo.id(x), x, "value mismatch");
    // }

    // /// @dev Fork test that runs against an Ethereum Mainnet fork. For this to work, you need to set
    // `API_KEY_ALCHEMY`
    // /// in your environment You can get an API key for free at https://alchemy.com.
    // function testFork_Example() external {
    //     // Silently pass this test if there is no API key.
    //     string memory alchemyApiKey = vm.envOr("API_KEY_ALCHEMY", string(""));
    //     if (bytes(alchemyApiKey).length == 0) {
    //         return;
    //     }

    //     // Otherwise, run the test against the mainnet fork.
    //     vm.createSelectFork({ urlOrAlias: "mainnet", blockNumber: 16_428_000 });
    //     address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    //     address holder = 0x7713974908Be4BEd47172370115e8b1219F4A5f0;
    //     uint256 actualBalance = IERC20(usdc).balanceOf(holder);
    //     uint256 expectedBalance = 196_307_713.810457e6;
    //     assertEq(actualBalance, expectedBalance);
    // }
    string source = "const game_id = args[0];"
                    "const url = 'https://v1.american-football.api-sports.io/games?id=' + game_id;"
                    "const gameRequest = Functions.makeHttpRequest({"
                    "url: url,"
                    "headers: {"
                    "   'Content-Type': 'application/json',"
                    "    'x-rapidapi-key': '0d7371b74cfe8afb33bf3dbc9abaa414',"
                    "    'x-rapidapi-host': 'v1.american-football.api-sports.io'"
                    "}"
                    "});"
                    "const gameResponse = await gameRequest;"
                    "if (gameResponse.error) {"
                    "throw Error('Request failed');"
                    "}"
                    "const ret = {"
                    "    id: gameResponse.data.response[0].game.id,"
                    "    finished: gameResponse.data.response[0].game.status.short == 'FT',"
                    "    home: gameResponse.data.response[0].scores.home.total,"
                    "    away: gameResponse.data.response[0].scores.away.total"
                    "}"
                    "let bits = 0;"
                    "bits |= ret.finished;"
                    "bits |= ret.home > ret.away ? 0 : 1 << 1;"
                    "bits |= Math.abs(ret.home - ret.away) << 2;"
                    "bits |= ret.id << 18;"
                    "return Functions.encodeUint256(bits);";
}
