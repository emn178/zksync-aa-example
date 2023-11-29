import { expect } from 'chai';
import { LOCAL_RICH_WALLETS, getWallet } from '../deploy/utils';
import { utils, Wallet } from "zksync-web3";
import * as ethers from "ethers";
import * as hre from "hardhat";
import { Deployer } from "@matterlabs/hardhat-zksync-deploy";

describe('GeneralPaymaster', () => {
  it('Should be the same with caller', async function () {
    const wallet = getWallet(LOCAL_RICH_WALLETS[0].privateKey);
    const deployer = new Deployer(hre, wallet);
    const provider = wallet.provider;
    const helloArtifact = await deployer.loadArtifact("Hello");
    const paymasterArtifact = await deployer.loadArtifact("GeneralPaymaster");

    // 建立測試合約
    const hello = await deployer.deploy(helloArtifact);

    // 建立 Paymaster
    const paymaster = await deployer.deploy(paymasterArtifact);

    // 發送一點 ETH 給 Paymaster 當 Gas
    await (
      await wallet.sendTransaction({
        to: paymaster.address,
        value: ethers.utils.parseEther('0.01')
      })
    ).wait();

    // 建立一個沒有 ETH 的錢包
    const owner = Wallet.createRandom().connect(provider);

    // 產生 Paymaster 參數
    const paymasterParams = utils.getPaymasterParams(paymaster.address, {
      type: "General",
      innerInput: '0x'
    });

    // 預估 Gas，實測設定多少就會花掉多少，不會退回
    const gasLimit = await hello.connect(owner).estimateGas.hi(
      {
        customData: {
          paymasterParams,
          gasPerPubdata: utils.DEFAULT_GAS_PER_PUBDATA_LIMIT
        }
      }
    );
    const gasPrice = await provider.getGasPrice();

    await (
      await hello
        .connect(owner)
        .hi({
          gasPrice,
          gasLimit,
          customData: {
            paymasterParams,
            gasPerPubdata: utils.DEFAULT_GAS_PER_PUBDATA_LIMIT,
          }
        })
    ).wait();

    const caller = await hello.caller(); // 這裡應該會是 owner.address
    expect(caller).to.equal(owner.address);
  });
});
