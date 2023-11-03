// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.21 <0.9.0;

import { FunctionsConsumerExample } from "../src/FunctionsConsumerExample.sol";
import { ChainBetFactory } from "../src/BettingFactory.sol";
import { ERC20 } from "lib/solmate/src/tokens/ERC20.sol";
import { BaseScript } from "./Base.s.sol";


// address: 0xB97183D2e5FA8954dcf7fbf16FC065d343278593
contract Mock20 is ERC20 {
    address me = 0xb9413c6FDA8Eac23E8F2cB2cc62D90881aBdD77d;
    address alsome = 0x465d1CfE1d94D427EdfE93E2010284d1eCb8839d;
    constructor() ERC20("Test", "TST", 6) {
        _mint(me, 100e6);
        _mint(alsome, 100e6);
    }
}

/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting
contract Deploy is BaseScript {
    address me = 0xb9413c6FDA8Eac23E8F2cB2cc62D90881aBdD77d;
    address alsome = 0x465d1CfE1d94D427EdfE93E2010284d1eCb8839d;

    function run() public broadcast returns (FunctionsConsumerExample foo) {
        ChainBetFactory factory = new ChainBetFactory(
            0xb83E47C2bC239B3bf370bc41e1459A34b41238D0,
            address(0xB97183D2e5FA8954dcf7fbf16FC065d343278593),
            1537,
            300000,
            bytes32("fun-ethereum-sepolia-1"),
            source
        );
    }

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
