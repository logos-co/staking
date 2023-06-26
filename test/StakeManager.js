const { expect } = require("chai");
const { ethers } = require("hardhat");
const {
  loadFixture
} = require("@nomicfoundation/hardhat-network-helpers");
var i =  0;
var j =  0;
describe("StakeManager contract", function () {
  async function deployTokenFixture() {
    const [owner, addr1, addr2, addr3] = await ethers.getSigners();
    const testToken = await ethers.deployContract("Token");
    await testToken.mint(addr1.address, 12 * 10^18);
    await testToken.mint(addr2.address, 24 * 10^18);
    await testToken.mint(addr3.address, 36 * 10^18);
    return { testToken, owner, addr1, addr2, addr3 };
  }

  async function deployStakeManager() {
    const { testToken, owner } = await loadFixture(deployTokenFixture);
    const stakeManager = await ethers.deployContract("StakeManager", [testToken.address, "0x0000000000000000000000000000000000000000"]);
    return { stakeManager, testToken, owner };
  }


  it("Deployment should be initialized zero", async function () {
    const { stakeManager, testToken, owner } = await loadFixture(deployStakeManager);
    expect(await stakeManager.totalSupply()).to.equal(0);
  });
});