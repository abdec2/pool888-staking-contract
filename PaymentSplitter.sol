// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/contracts/finance/PaymentSplitter.sol";

contract pool888FeeCollector is PaymentSplitter {

    constructor(address[] memory payees, uint256[] memory shares_) PaymentSplitter (payees, shares_) {}
}


// ["0x5baA0f14D09864929c5fC8AbDfDc466dcb72be9d", "0x64DC48F2Ae171f7Ae966f15844eF2f8751665110"]
// [90, 10]