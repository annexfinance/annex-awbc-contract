const deployed = {
  agencyWolfBillionaireClub: "",
};

const func = async function (hre) {
  const { deployments, getNamedAccounts, ethers } = hre;
  const { get, deploy, read, execute } = deployments;
  const { deployer } = await getNamedAccounts();

  const agencyWolfBillionaireClub = deployed.agencyWolfBillionaireClub
    ? { address: deployed.agencyWolfBillionaireClub }
    : await deploy("AgencyWolfBillionaireClub", { from: deployer, log: true, 
      args: ["AgencyWolfBillionaireClub", "AWBC", "https://nftassets.annex.finance/ipfs/QmeHoeon52U4HYuemkfuKtzxcSZV2xSW69rBeEKKPzav4G", "0xb75f3F9D35d256a94BBd7A3fC2E16c768E17930E"] });
};

func.tags = ["nft", "annex"];
module.exports = func;
