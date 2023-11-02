// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.21 <0.9.0;

import { FunctionsConsumerExample } from "../src/FunctionsConsumerExample.sol";

import { BaseScript } from "./Base.s.sol";

/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting
contract Deploy is BaseScript {
    function run() public broadcast returns (FunctionsConsumerExample foo) {
        foo = new FunctionsConsumerExample(0xb83E47C2bC239B3bf370bc41e1459A34b41238D0);
    }
}
