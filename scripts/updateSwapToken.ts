const { ethers } = require("hardhat");

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with the account: " + deployer.address);
    const EIGHT_HOURS = "28800";
    const ONE_DAY = "86400";

    const VectorAddress = "0x2F48930c5947e350F913634952a27085D2520985";
    const wETHToLP = "0xA7F55F41f548DE5D7cE7E964fDf323A7e31b0D70";

    const vector = await ethers.getContractAt(
        "contracts/tokens/Vector.sol:Vector",
        VectorAddress
    );

    console.log(await vector.swapPercent());
    console.log(await vector.swapTokensAtAmount());

    // await vector.updateSwapTokensAtPercent("10", {gasLimit: 1_000_000});
    // await vector.excludeFromFees(wETHToLP, true, {gasLimit: 1_000_000})
}

main()
    .then(() => process.exit())
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
