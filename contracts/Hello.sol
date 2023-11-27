//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

contract Hello {
  address public caller;

  function hi() external {
    caller = msg.sender;
  }
}
