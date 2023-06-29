// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log(`Deploying contracts to ${network.name} (${network.config.chainId}) with the account: ${deployer.address}`);
  const miniMeTokenFactory = await ethers.deployContract("MiniMeTokenFactory");
  const miniMeToken = await ethers.deployContract(
    "MiniMeToken", [
      miniMeTokenFactory.target,
      ethers.ZeroAddress,
      0,
      network.config.chainId == 1 ? "Status Network Token" :  "Status Test Token",
      18,
      network.config.chainId == 1 ? "SNT" : "STT",
      true
    ]);

  const tokenController = await ethers.deployContract(
    network.config.chainId == 1 ? "SNTPlaceHolder" : "SNTFaucet",
    [
      deployer.address,
      miniMeToken.target
    ]
  );
  await miniMeToken.changeController(tokenController.target);
  console.log(
    `${network.config.chainId == 1 ? "SNT" : "STT"} ${miniMeToken.target} controlled by ${await miniMeToken.controller()}`
  );
  console.log(
    `${network.config.chainId == 1 ? "SNTPlaceHolder" : "SNTFaucet"} ${tokenController.target} owned by ${await tokenController.owner()}`
  );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
