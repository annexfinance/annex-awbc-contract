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
    info.agencyWolfBillionaireClub = await AgencyWolfBillionaireClub.deploy("AgencyWolfBillionaireClub", "AgencyWolfBillionaireClub");
  });

  it("Set Sale Status", async function () {
    await info.agencyWolfBillionaireClub.setSaleStatus(true);
  });

  it("Start Sale Mint", async function () {
    await expect(info.agencyWolfBillionaireClub.connect(info.minter1Signer).mint(info.minter1, 5, { value: info.mintFee(5) })).to.be.emit(
      info.agencyWolfBillionaireClub,
      "Transfer"
    );

    // can't mint bigger than max
    await expect(info.agencyWolfBillionaireClub.connect(info.minter1Signer).mint(info.minter1, 11, { value: info.mintFee(11) })).to.be.reverted;

    await expect(info.agencyWolfBillionaireClub.connect(info.minter1Signer).mint(info.minter1, 5, { value: info.mintFee(5) })).to.be.emit(
      info.agencyWolfBillionaireClub,
      "Transfer"
    );
    let totalSupply = await info.agencyWolfBillionaireClub.totalSupply();
    expect(totalSupply.eq(10)).to.equal(true);
  });
});
