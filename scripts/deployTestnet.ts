const { ethers } = require("hardhat");

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with the account: " + deployer.address);
    const EIGHT_HOURS = "28800";
    const ONE_DAY = "86400";

    const routerAddress = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";

    const goerliWETH = "0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6";

    const VEC = await ethers.getContractFactory("Vector");
    const vec = await VEC.deploy({ gasLimit: 8_000_000 });

    const VETH = await ethers.getContractFactory("VectorETH");
    const vETH = await VETH.deploy({ gasLimit: 8_000_000 });

    const StakedVectorETH = await ethers.getContractFactory("StakedVectorETH");
    const svETH = await StakedVectorETH.deploy(vETH.getAddress(), { gasLimit: 8_000_000 });

    const Treasury = await ethers.getContractFactory("VectorTreasury");
    const treasury = await Treasury.deploy(vec.getAddress(), vETH.getAddress(), {
        gasLimit: 8_000_000,
    });

    const SVEC = await ethers.getContractFactory("sVEC");
    const sVEC = await SVEC.deploy({ gasLimit: 8_000_000 });

    const Staking = await ethers.getContractFactory("VECStaking");
    const staking = await Staking.deploy(vec.getAddress(), sVEC.getAddress(), "600", "600", {
        gasLimit: 8_000_000,
    });

    const Distributor = await ethers.getContractFactory("Distributor");
    const distributor = await Distributor.deploy(
        treasury.getAddress(),
        vec.getAddress(),
        vETH.getAddress(),
        svETH.getAddress(),
        staking.getAddress(),
        { gasLimit: 8_000_000 }
    );

    await vec.initialize(treasury.getAddress(), distributor.getAddress(), vETH.getAddress(), {
        gasLimit: 1_000_000,
    });
    await treasury.addApprovedMinter(distributor.getAddress({ gasLimit: 8_000_000 }));

    await sVEC.setIndex("1000000000", { gasLimit: 8_000_000 });
    await sVEC.initialize(staking.getAddress(), { gasLimit: 8_000_000 });

    await staking.setDistributor(distributor.getAddress(), { gasLimit: 8_000_000 });
    await distributor.setVECRate("250", { gasLimit: 8_000_000 });
    await distributor.setsvETHReward(ethers.parseEther("0.5"), { gasLimit: 8_000_000 });

    await vETH.addRestakedLST(goerliWETH, ethers.parseEther("1.0"), { gasLimit: 8_000_000 });
    await vec
        .connect(deployer)
        .approve(routerAddress, "1000000000000000000000", { gasLimit: 8_000_000 });

    const router = await ethers.getContractAt(
        "contracts/interface/IUniswapV2Router02.sol:IUniswapV2Router02",
        routerAddress
    );

    await router
        .connect(deployer)
        .addLiquidityETH(
            vec.getAddress(),
            "200000000000000",
            0,
            0,
            treasury.getAddress(),
            "10000000000000000",
            { value: ethers.parseEther("50.0"), gasLimit: 8_000_000 }
        );

    await vec.enableTrading({ gasLimit: 8_000_000 });

    console.log("LP: " + (await vec.uniswapV2Pair()));
    console.log("VEC: " + (await vec.getAddress()));
    console.log("vETH: " + (await vETH.getAddress()));
    console.log("Staked vETH: " + (await svETH.getAddress()));
    console.log("VEC Treasury: " + (await treasury.getAddress()));
    console.log("Staked VEC: " + (await sVEC.getAddress()));
    console.log("Staking Contract: " + (await staking.getAddress()));
    console.log("Distributor: " + (await distributor.getAddress()));
}

main()
    .then(() => process.exit())
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
