const { ethers } = require("hardhat");

async function main() {
  console.log("Deploying DAO Treasury Management contract...");

  // Get the contract factory
  const DAOTreasury = await ethers.getContractFactory("DAOTreasury");
  
  // Deploy the contract
  const daoTreasury = await DAOTreasury.deploy();
  
  // Wait for deployment to finish
  await daoTreasury.deployed();
  
  console.log(`DAOTreasury deployed to: ${daoTreasury.address}`);
  console.log(`Transaction hash: ${daoTreasury.deployTransaction.hash}`);
  
  console.log("Waiting for block confirmations...");
  // Wait for 5 block confirmations
  await daoTreasury.deployTransaction.wait(5);
  console.log("Contract deployment confirmed!");
  
  // Verify contract on block explorer if on a network that supports it
  console.log("You can now verify the contract on the block explorer using:");
  console.log(`npx hardhat verify --network coreTestnet2 ${daoTreasury.address}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
