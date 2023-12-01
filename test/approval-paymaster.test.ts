import { expect } from 'chai';
import { LOCAL_RICH_WALLETS, getWallet } from '../deploy/utils';
import { utils, Wallet } from 'zksync-web3';
import * as ethers from 'ethers';
import * as hre from 'hardhat';
import { Deployer } from '@matterlabs/hardhat-zksync-deploy';

describe('ApprovalPaymaster', () => {
  it('Should be the same with caller', async function () {
    const wallet = getWallet(LOCAL_RICH_WALLETS[0].privateKey);
    const deployer = new Deployer(hre, wallet);
    const provider = wallet.provider;
    const tokenArtifact = await deployer.loadArtifact('MyToken');
    const helloArtifact = await deployer.loadArtifact('Hello');
    const paymasterArtifact = await deployer.loadArtifact('ApprovalPaymaster');

    // 建立 Token
    const token = await deployer.deploy(tokenArtifact);

    // 建立測試合約
    const hello = await deployer.deploy(helloArtifact);

    // 建立 Paymaster
    const paymaster = await deployer.deploy(paymasterArtifact, [token.address]);

    // 發送一點 ETH 給 Paymaster 當 Gas
    await (
      await wallet.sendTransaction({
        to: paymaster.address,
        value: ethers.utils.parseEther('0.01')
      })
    ).wait();

    // 建立一個沒有 ETH 的錢包
    const owner = Wallet.createRandom().connect(provider);

    // 發一點 Token 給 owner
    await token.transfer(owner.address, ethers.utils.parseEther('1000'));

    // 產生 Paymaster 參數
    const baseParams: any = {
      type: 'ApprovalBased',
      token: token.address,
      innerInput: '0x'
    };
    let paymasterParams = utils.getPaymasterParams(paymaster.address, {
      ...baseParams,
      minimalAllowance: ethers.utils.parseEther('30')
    });

    // 預估 Gas
    const gasLimit = await hello.connect(owner).estimateGas.hi(
      {
        customData: {
          paymasterParams,
          gasPerPubdata: utils.DEFAULT_GAS_PER_PUBDATA_LIMIT
        }
      }
    );
    const gasPrice = await provider.getGasPrice();

    // 重新計算實際需要的 Token
    paymasterParams = utils.getPaymasterParams(paymaster.address, {
      ...baseParams,
      minimalAllowance: gasLimit.mul(gasPrice).mul(2000)
    });

    await (
      await hello
        .connect(owner)
        .hi({
          gasPrice,
          gasLimit,
          customData: {
            paymasterParams: paymasterParams,
            gasPerPubdata: utils.DEFAULT_GAS_PER_PUBDATA_LIMIT
          }
        })
    ).wait();

    const caller = await hello.caller(); // 這裡應該會是 owner.address
    expect(caller).to.equal(owner.address);
  });
});
