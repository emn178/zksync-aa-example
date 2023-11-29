
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@matterlabs/zksync-contracts/l2/system-contracts/Constants.sol";
import "@matterlabs/zksync-contracts/l2/system-contracts/interfaces/IAccount.sol";
import "@matterlabs/zksync-contracts/l2/system-contracts/libraries/TransactionHelper.sol";
import "@matterlabs/zksync-contracts/l2/system-contracts/libraries/SystemContractsCaller.sol";
import "@matterlabs/zksync-contracts/l2/system-contracts/libraries/EfficientCall.sol";

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract MyAccount is IAccount {
  using TransactionHelper for Transaction;

  address public owner;

  // 某些方法限制只有 bootloader 能呼叫
  modifier onlyBootloader() {
    require(msg.sender == BOOTLOADER_FORMAL_ADDRESS, "Only bootloader can call this method");
    _;
  }

  constructor(address _owner) {
    owner = _owner;
  }

  function validateTransaction(
    bytes32,
    bytes32 _suggestedSignedHash, // 使用此參數
    Transaction calldata _transaction
  ) external payable override onlyBootloader returns (bytes4 magic) {
    magic = _validateTransaction(_suggestedSignedHash, _transaction);
  }

  function _validateTransaction(
    bytes32 _suggestedSignedHash, // 新增參數
    Transaction calldata _transaction
  ) internal returns (bytes4 magic) {
    // 使用掉 Nonce
    SystemContractsCaller.systemCallWithPropagatedRevert(
      Utils.safeCastToU32(gasleft()),
      address(NONCE_HOLDER_SYSTEM_CONTRACT),
      0,
      abi.encodeCall(INonceHolder.incrementMinNonceIfEquals, (_transaction.nonce))
    );

    // 檢驗是否能支付手續費
    uint256 totalRequiredBalance = _transaction.totalRequiredBalance();
    require(totalRequiredBalance <= address(this).balance, "Not enough balance for fee + value");

    bytes32 txHash = _suggestedSignedHash != bytes32(0) ? _suggestedSignedHash : _transaction.encodeHash();
    if (_isValidSignature(txHash, _transaction.signature)) {
      magic = ACCOUNT_VALIDATION_SUCCESS_MAGIC;
    }
  }

  function executeTransaction(
    bytes32,
    bytes32,
    Transaction calldata _transaction
  ) external payable override onlyBootloader {
    _executeTransaction(_transaction);
  }

  // 使用官方的 EfficientCall 方式處理
  function _executeTransaction(Transaction calldata _transaction) internal {
    address to = address(uint160(_transaction.to));
    uint128 value = Utils.safeCastToU128(_transaction.value);
    bytes calldata data = _transaction.data;
    uint32 gas = Utils.safeCastToU32(gasleft());

    bool isSystemCall;
    if (to == address(DEPLOYER_SYSTEM_CONTRACT) && data.length >= 4) {
      bytes4 selector = bytes4(data[:4]);
      isSystemCall =
        selector == DEPLOYER_SYSTEM_CONTRACT.create.selector ||
        selector == DEPLOYER_SYSTEM_CONTRACT.create2.selector ||
        selector == DEPLOYER_SYSTEM_CONTRACT.createAccount.selector ||
        selector == DEPLOYER_SYSTEM_CONTRACT.create2Account.selector;
    }
    bool success = EfficientCall.rawCall(gas, to, value, data, isSystemCall);
    if (!success) {
      EfficientCall.propagateRevert();
    }
  }

  // 如果允許由外部執行，否則也可以留空
  function executeTransactionFromOutside(
    Transaction calldata _transaction
  ) external payable {
    _validateTransaction(bytes32(0), _transaction);
    _executeTransaction(_transaction);
  }

  function _isValidSignature(
    bytes32 _hash,
    bytes memory _signature
  ) internal view virtual returns (bool) {
    return ECDSA.recover(_hash, _signature) == owner;
  }

  function payForTransaction(
    bytes32,
    bytes32,
    Transaction calldata _transaction
  ) external payable override onlyBootloader {
    bool success = _transaction.payToTheBootloader();
    require(success, "Failed to pay the fee to the operator");
  }

  function prepareForPaymaster(
    bytes32,
    bytes32,
    Transaction calldata _transaction
  ) external payable override onlyBootloader {
    _transaction.processPaymasterInput();
  }

  fallback() external payable {
    // bootloader 不應該會呼叫
    assert(msg.sender != BOOTLOADER_FORMAL_ADDRESS);
  }

  // 必須要能收 ETH
  receive() external payable {
  }
}
