import { expect } from 'chai';
import { LOCAL_RICH_WALLETS, getWallet } from '../deploy/utils';
import { utils, Wallet, EIP712Signer, types } from 'zksync-web3';
import * as ethers from 'ethers';
import * as hre from 'hardhat';
import { Deployer } from '@matterlabs/hardhat-zksync-deploy';

describe('Hello', function () {
  it('Should be the same with caller', async function () {
    // const wallet = getWallet();
    const wallet = getWallet(LOCAL_RICH_WALLETS[0].privateKey);
    const deployer = new Deployer(hre, wallet);
    const provider = wallet.provider;
    const helloArtifact = await deployer.loadArtifact('Hello');
    const factoryArtifact = await deployer.loadArtifact('MyFactory');
    const accountArtifact = await deployer.loadArtifact('MyAccount');

    // 建立測試合約
    const hello = await deployer.deploy(helloArtifact);

    // 建立 Factory
    const factory = await deployer.deploy(
      factoryArtifact,
      [utils.hashBytecode(accountArtifact.bytecode)],
      undefined,
      [accountArtifact.bytecode]
    );

    // 建立一個錢包
    const owner = Wallet.createRandom();

    // 產生 salt 亂數, 這邊範例使用固定的 0
    const salt = ethers.constants.HashZero;

    // 產生抽象帳戶
    (await factory.deployAccount(salt, owner.address)).wait();

    // 由於 deployAccount() 回傳的地址沒辦法直接拿到，這裡使用鏈下預測生成的地址，實務上也可用 event 之類的方式丟出來
    const abiCoder = new ethers.utils.AbiCoder();
    const accountAddress = utils.create2Address(
      factory.address,
      await factory.aaBytecodeHash(),
      salt,
      abiCoder.encode(['address'], [owner.address])
    );

    // 發送一點 ETH 給這個帳戶當 Gas
    await (
      await wallet.sendTransaction({
        to: accountAddress,
        value: ethers.utils.parseEther('0.01')
      })
    ).wait();

    let aaTx = await hello.populateTransaction.hi();
    aaTx = {
      ...aaTx,
      from: accountAddress,
      gasLimit: await provider.estimateGas(aaTx),
      gasPrice: await provider.getGasPrice(),
      chainId: (await provider.getNetwork()).chainId,
      nonce: await provider.getTransactionCount(accountAddress),
      type: 113,
      customData: {
        gasPerPubdata: utils.DEFAULT_GAS_PER_PUBDATA_LIMIT,
      } as types.Eip712Meta,
      value: ethers.BigNumber.from(0)
    };

    // owner 簽署這個交易
    const signer = new EIP712Signer(owner, aaTx.chainId!);
    aaTx.customData = {
      ...aaTx.customData,
      customSignature: await signer.sign(aaTx)
    };
    (await provider.sendTransaction(utils.serialize(aaTx))).wait();

    const caller = await hello.caller(); // 這裡應該會是 accountAddress
    expect(caller).to.equal(accountAddress);
  });
});
