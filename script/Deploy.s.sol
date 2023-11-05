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

    address sep_ccip_router = 0xD0daae2231E9CB96b94C8512223533293C3693Bf;
    address sep_functions_router = 0xb83E47C2bC239B3bf370bc41e1459A34b41238D0;
    uint64 sep_chain_selector = 16015286601757825753;
    address sep_ccip_token = 0xFd57b4ddBf88a4e07fF4e34C487b99af2Fe82a05;
    address sep_wnative = 0x097D90c9d3E0B50Ca60e1ae45F6A81010f9FB534;
    uint sep_subscriptionId = 1537;
    bytes32 sep_donID = bytes32("fun-ethereum-sepolia-1");

    address fuji_ccip_router = 0x554472a2720E5E7D5D3C817529aBA05EEd5F82D8;
    address fuji_functions_router = 0xA9d587a00A31A52Ed70D6026794a8FC5E2F5dCb0;
    uint64 fuji_chain_selector = 14767482510784806043;
    address fuji_ccip_token = 0xD21341536c5cF5EB1bcb58f6723cE26e8D8E90e4;
    address fuji_wnative = 0xd00ae08403B9bbb9124bB305C09058E32C39A48c;
    uint fuji_subscriptionId = 399;
    bytes32 fuji_donID = bytes32("fun-avalanche-fuji-1");

    function run() public broadcast returns (FunctionsConsumerExample foo) {
        ChainBetFactory factory = new ChainBetFactory(
            fuji_ccip_router,
            fuji_functions_router,
            sep_chain_selector,
            fuji_ccip_token,
            fuji_wnative,
            fuji_subscriptionId,
            1000000,
            fuji_donID,
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
