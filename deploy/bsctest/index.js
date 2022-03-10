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
      args: ["AgencyWolfBillionaireClub"] });
};

func.tags = ["nft", "annex"];
module.exports = func;
