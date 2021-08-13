const { network, ethers } = require("hardhat");

module.exports = async ({ getNamedAccounts, deployments }) => {
    const { deployer } = await getNamedAccounts();    
    const { deploy } = deployments;
    
    await deploy("SafeBscOrderBook", {
        from: deployer,
        args: [ethers.utils.parseEther("0.01")],
        log: true,
    });
};

module.exports.tags = ["SafeBscOrderBook"]
