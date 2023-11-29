// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@matterlabs/zksync-contracts/l2/system-contracts/Constants.sol";
import "@matterlabs/zksync-contracts/l2/system-contracts/interfaces/IPaymaster.sol";
import "@matterlabs/zksync-contracts/l2/system-contracts/interfaces/IPaymasterFlow.sol";

contract GeneralPaymaster is IPaymaster {
  using Address for address payable;

  // 某些方法限制只有 bootloader 能呼叫
  modifier onlyBootloader() {
    require(msg.sender == BOOTLOADER_FORMAL_ADDRESS, "Only bootloader can call this method");
    _;
  }

  function validateAndPayForPaymasterTransaction(
    bytes32,
    bytes32,
    Transaction calldata _transaction
  ) external payable onlyBootloader returns (bytes4 magic, bytes memory context) {
    // 目前固定回傳這個值，後面直接用 require 或 revert 做其他驗證
    magic = PAYMASTER_VALIDATION_SUCCESS_MAGIC;
    require(
      _transaction.paymasterInput.length >= 4,
      "The standard paymaster input must be at least 4 bytes long"
    );

    bytes4 paymasterInputSelector = bytes4(_transaction.paymasterInput[0:4]);
    if (paymasterInputSelector == IPaymasterFlow.general.selector) {
      // 計算要多少 ETH 當作 Gas 費
      uint256 requiredETH = _transaction.gasLimit * _transaction.maxFeePerGas;

      // 支付 Gas 手續費
      payable(BOOTLOADER_FORMAL_ADDRESS).sendValue(requiredETH);
    } else {
      revert("Unsupported paymaster flow in paymasterParams.");
    }
  }

  function postTransaction(
    bytes calldata,
    Transaction calldata,
    bytes32,
    bytes32,
    ExecutionResult,
    uint256
  ) external payable override onlyBootloader {}

  // 必須要能收 ETH
  receive() external payable {}
}
