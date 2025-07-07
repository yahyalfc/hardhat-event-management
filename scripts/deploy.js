const { ethers } = require("hardhat");

async function main() {
  const EventContract = await ethers.getContractFactory("EventContract");
  const eventContract = await EventContract.deploy();

  // Wait for deployment to complete
  await eventContract.waitForDeployment();

  // Use getAddress() instead of .address in ethers v6
  console.log(
    "Contract Deployed to Address:",
    await eventContract.getAddress()
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
