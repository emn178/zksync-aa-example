// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@matterlabs/zksync-contracts/l2/system-contracts/Constants.sol";
import "@matterlabs/zksync-contracts/l2/system-contracts/interfaces/IPaymaster.sol";
import "@matterlabs/zksync-contracts/l2/system-contracts/interfaces/IPaymasterFlow.sol";

contract ApprovalPaymaster is IPaymaster {
  using Address for address payable;
  using SafeERC20 for IERC20;

  // 假設 token 是 USD，以太價格為 2000 USD
  uint256 public price = 2000;
  address public allowedToken;

  // 某些方法限制只有 bootloader 能呼叫
  modifier onlyBootloader() {
    require(msg.sender == BOOTLOADER_FORMAL_ADDRESS, "Only bootloader can call this method");
    _;
  }

  constructor(address _erc20) {
    allowedToken = _erc20;
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
    if (paymasterInputSelector == IPaymasterFlow.approvalBased.selector) {
      // 此類型會帶的一些資料，可以自訂驗證方式，amount 是 user 授權的數字，可以視為 user 最多願意支付多少
      (address token, uint256 amount, bytes memory data) = abi.decode(
        _transaction.paymasterInput[4:],
        (address, uint256, bytes)
      );

      // 檢驗是否支援使用此 Token 支付，合約可實作支援多種
      require(token == allowedToken, "Invalid token");

      // 計算要多少 ETH 當作 Gas 費
      uint requiredETH = _transaction.gasLimit * _transaction.maxFeePerGas;

      // 計算換成成 Token 要收取多少
      uint requiredToken = requiredETH * price;
      require(amount >= requiredToken, "Not the required amount of tokens sent");

      // 收取 Token 作為 Gas 手續費
      address userAddress = address(uint160(_transaction.from));
      IERC20(token).safeTransferFrom(userAddress, address(this), requiredToken);

      // 支付 Gas 手續費
      payable(BOOTLOADER_FORMAL_ADDRESS).sendValue(requiredETH);
    } else {
      revert("Unsupported paymaster flow");
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
