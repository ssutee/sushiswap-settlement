const { network, ethers } = require("hardhat");

module.exports = async ({ getNamedAccounts, deployments }) => {
    const { deployer, feeCollector } = await getNamedAccounts();
    const { deterministic } = deployments;

    const { deploy } = await deterministic("SafeBscRouter", {
        from: deployer,
        log: true,
        args: [ethers.constants.WeiPerEther, feeCollector],
    });
    await deploy();
};

module.exports.tags = ["SafeBscRouter"];
