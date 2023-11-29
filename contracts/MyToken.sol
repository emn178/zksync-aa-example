// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract MyToken is ERC20Burnable {
  constructor() ERC20("MyToken", "MT") {
    uint256 initialSupply = 100_000_000 * (10 ** 18);
    _mint(msg.sender, initialSupply);
  }
}
