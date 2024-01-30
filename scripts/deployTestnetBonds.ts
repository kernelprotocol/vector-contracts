const { ethers } = require("hardhat");

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with the account: " + deployer.address);

    const goerliWETH = "0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6";
    const vETH = "0x85Dfb7740Df31Ee454cf11bA20040643D709E6eb";
    const treasuryAddress = "0xe2ce544CFEF9b5bE29B25d4fDcA0b0cE10e9bE5f";
    const VETHETHLP = "0x4A210cA222BF780721056FB5713FF89C13263A14";

    const VectorBonding = await ethers.getContractFactory("VectorBonding");

    const vETHETHBOND = await VectorBonding.deploy(treasuryAddress, vETH, VETHETHLP, true, {
        gasLimit: 8_000_000,
    });
    const wethBond = await VectorBonding.deploy(treasuryAddress, vETH, goerliWETH, false, {
        gasLimit: 8_000_000,
    });
    const wETHToLPBonding = await VectorBonding.deploy(treasuryAddress, vETH, goerliWETH, false, {
        gasLimit: 8_000_000,
    });

    console.log("vETH/ETH Bond: " + (await vETHETHBOND.getAddress()));
    console.log("wETH Bond: " + (await wethBond.getAddress()));
    console.log("wETHToLP Bond: " + (await wETHToLPBonding.getAddress()));

    await vETHETHBOND.setBondTerms("0", "604800", { gasLimit: 8_000_000 });
    await vETHETHBOND.setFeeAndFeeTo(deployer.getAddress(), "500000", { gasLimit: 8_000_000 });

    await wethBond.setBondTerms("0", "604800", { gasLimit: 8_000_000 });
    await wethBond.setFeeAndFeeTo(deployer.getAddress(), "50000", { gasLimit: 8_000_000 });

    await wETHToLPBonding.setBondTerms("0", "604800", { gasLimit: 8_000_000 });
    await wETHToLPBonding.setFeeAndFeeTo(deployer.getAddress(), "50000", { gasLimit: 8_000_000 });

    const treasury = await ethers.getContractAt(
        "contracts/treasury/VectorTreasury.sol:VectorTreasury",
        treasuryAddress
    );

    await treasury.addApprovedMinter(vETHETHBOND.getAddress(), { gasLimit: 8_000_000 });
    await treasury.addApprovedMinter(wethBond.getAddress(), { gasLimit: 8_000_000 });
    await treasury.addApprovedMinter(wETHToLPBonding.getAddress(), { gasLimit: 8_000_000 });

    await vETHETHBOND.initializeBond(
        "10000",
        "604800",
        "70000000000000",
        "250",
        "25000000000",
        "8250000000",
        "0",
        { gasLimit: 8_000_000 }
    );
    await wethBond.initializeBond(
        "25000",
        "604800",
        "160000000000000",
        "250",
        "25000000000",
        "7500000000",
        "1",
        { gasLimit: 8_000_000 }
    );
    await wETHToLPBonding.initializeBond(
        "25000",
        "604800",
        "160000000000000",
        "250",
        "25000000000",
        "7500000000",
        "2",
        { gasLimit: 8_000_000 }
    );

    console.log("DONE");
}

main()
    .then(() => process.exit())
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
