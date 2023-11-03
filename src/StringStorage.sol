// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;
import { console } from "lib/forge-std/src/console.sol";
contract StringStorage {
    string public value;

    constructor(string memory _value) {
        console.log(_value);
        value = _value;
    }

    function update(string memory _value) public {
        value = _value;
    }
}