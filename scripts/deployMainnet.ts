const { ethers } = require("hardhat");

async function main() {

    const [deployer] = await ethers.getSigners();
    console.log('Deploying contracts with the account: ' + deployer.address);

    const EIGHT_HOURS = "28800";
    const ONE_DAY = "86400";

    const WETH = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"

    const VEC = await ethers.getContractFactory('Vector');
    const vec = await VEC.deploy();

    const VETH = await ethers.getContractFactory('VectorETH');
    const vETH = await VETH.deploy();

    const StakedVectorETH = await ethers.getContractFactory("StakedVectorETH");
    const svETH = await StakedVectorETH.deploy(vETH.getAddress()); 

    const Treasury = await ethers.getContractFactory('VectorTreasury');
    const treasury = await Treasury.deploy(vec.getAddress(), vETH.getAddress());

    const SVEC = await ethers.getContractFactory('sVEC');
    const sVEC = await SVEC.deploy();

    const Staking = await ethers.getContractFactory('VECStaking');
    const staking = await Staking.deploy(vec.getAddress(), sVEC.getAddress(), EIGHT_HOURS, ONE_DAY);

    const Distributor = await ethers.getContractFactory('Distributor');
    const distributor = await Distributor.deploy(treasury.getAddress(), vec.getAddress(), vETH.getAddress(), staking.getAddress());

    await vec.initialize(treasury.getAddress(), distributor.getAddress(), vETH.getAddress());
    await treasury.addApprovedMinter(distributor.getAddress());

    await sVEC.setIndex('1000000000');
    await sVEC.initialize(staking.getAddress());

    await staking.setDistributor(distributor.getAddress());
    await distributor.setVECRate("250");
    await distributor.setsvETHReward("500000000000000000");

    await vETH.addRestakedLST(WETH, ethers.parseEther("0.9"));
    await vETH.deposit(WETH, treasury.getAddress(), ethers.parseEther("15"));
    

    console.log("VEC: " + await vec.getAddress());
    console.log("vETH: " + await vETH.getAddress());
    console.log("Staked vETH: " + (await svETH.getAddress()));
    console.log("VEC Treasury: " + await treasury.getAddress());
    console.log("Staked VEC: " + await sVEC.getAddress());
    console.log("Staking Contract: " + await staking.getAddress());
    console.log("Distributor: " + await distributor.getAddress());
}

main()
    .then(() => process.exit())
    .catch(error => {
        console.error(error);
        process.exit(1);
})