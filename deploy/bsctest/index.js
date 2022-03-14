const deployed = {
  annexWolfNFT: "",
  annexBoostFarm: "",
};

const func = async function (hre) {
  const { deployments, getNamedAccounts, ethers } = hre;
  const { get, deploy, read, execute } = deployments;
  const { deployer } = await getNamedAccounts();

  const annexWolfNFT = deployed.annexWolfNFT
    ? { address: deployed.annexWolfNFT }
    : await deploy("AnnexWolfNFT", { from: deployer, log: true, 
      args: [
        "AnnexWolfNFT",
        "AWN",
        "https://nftassets.annex.finance/ipfs/QmeHoeon52U4HYuemkfuKtzxcSZV2xSW69rBeEKKPzav4G",
        "0xb75f3F9D35d256a94BBd7A3fC2E16c768E17930E"
      ] });

  // const annexBoostFarm = deployed.annexBoostFarm
  //   ? { address: deployed.annexBoostFarm }
  //   : await deploy("AnnexBoostFarm", { from: deployer, log: true, 
  //     args: [
  //       "0xb75f3F9D35d256a94BBd7A3fC2E16c768E17930E",
  //       annexWolfNFT.address,
  //       "0x79395B873119a42c3B9E4211FCEA9CC0358769Ed",
  //       "10000000000000000", //annexPerBlock
  //       "10000000000000000", // boostAnnexPerBlock
  //       17437841, // bonusEndBlock
  //       17507606
  //     ] });
};

func.tags = ["nft", "annex"];
module.exports = func;
