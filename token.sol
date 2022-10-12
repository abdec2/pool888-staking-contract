// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MyToken is ERC20 {
    uint8 private tokenDecimals;

    constructor(
        uint _initial_supply, 
        string memory _name, 
        string memory _symbol, 
        uint8 _decimals
    ) ERC20(_name, _symbol) {
        _mint(msg.sender, _initial_supply * 10 ** _decimals);
        tokenDecimals = _decimals;
    }

    function decimals() public view virtual override returns (uint8) {
        return tokenDecimals;
    }
}
