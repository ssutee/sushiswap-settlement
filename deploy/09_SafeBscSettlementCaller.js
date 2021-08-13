const { network, ethers } = require("hardhat");

module.exports = async ({ getNamedAccounts, deployments }) => {
    const { deployer } = await getNamedAccounts();
    const { deploy } = deployments;

    const settlement = await ethers.getContract("SafeBscSettlement", deployer);
    if (network.name !== "mainnet") {
        await deploy("SafeBscSettlementCaller", {
            args: [settlement.address],
            from: deployer,
            log: true,
        });
    }
};

module.exports.dependencies = ['SafeBscSettlement']