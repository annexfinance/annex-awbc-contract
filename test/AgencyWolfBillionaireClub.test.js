const { expect } = require("chai");
const { ethers, getNamedAccounts, web3 } = require("hardhat");

function fromWei(number, decimals = 18) {
  return web3.utils.fromWei(number.toString() + new Array(18 - decimals).fill(0).join(""));
}

describe("AgencyWolfBillionaireClub", function () {
  const info = {
    mintPrice: web3.utils.toWei("0.04"),
    mintFee: (amount = 1) => web3.utils.toWei((0.04 * amount).toString()),
  };

  before(async function () {
    const namedAccounts = await getNamedAccounts();
    info.deployer = namedAccounts.deployer;
    info.deployerSigner = await ethers.provider.getSigner(info.deployer);
    info.member1 = namedAccounts.member1;
    info.member1Signer = await ethers.provider.getSigner(info.member1);
    info.member2 = namedAccounts.member2;
    info.member2Signer = await ethers.provider.getSigner(info.member2);
    info.minter1 = namedAccounts.minter1;
    info.minter1Signer = await ethers.provider.getSigner(info.minter1);
    info.minter2 = namedAccounts.minter2;
    info.minter2Signer = await ethers.provider.getSigner(info.minter2);
  });

  it("Contract Deploy", async function () {
    const AgencyWolfBillionaireClub = await ethers.getContractFactory("AgencyWolfBillionaireClub");
    info.agencyWolfBillionaireClub = await AgencyWolfBillionaireClub.deploy(
      "AgencyWolfBillionaireClub",
      "AWBC",
      "https://nftassets.annex.finance/ipfs/QmeHoeon52U4HYuemkfuKtzxcSZV2xSW69rBeEKKPzav4G",
      "0x79395B873119a42c3B9E4211FCEA9CC0358769Ed"
    );
  });

  it("Set Sale Date", async function () {
    await info.agencyWolfBillionaireClub.setPublicSaleDate(parseInt(Date.now() / 1000));
  });

  it("Start Sale Mint", async function () {
    await expect(info.agencyWolfBillionaireClub.connect(info.deployerSigner).gift(1, info.minter1)).to.be.emit(
      info.agencyWolfBillionaireClub,
      "Transfer"
    );

    // can't mint bigger than max
    await expect(info.agencyWolfBillionaireClub.connect(info.minter1Signer).gift(1, info.minter1)).to.be.reverted;

    let totalSupply = await info.agencyWolfBillionaireClub.totalSupply();
    expect(totalSupply.eq(1)).to.equal(true);
  });
});
