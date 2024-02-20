const { ethers } = require("hardhat");
const { expect } = require("chai");

describe("Test", () => {
    let routerAddress,
        router,
        VEC,
        vec,
        VETH,
        vETH,
        Treasury,
        treasury,
        SVEC,
        sVEC,
        Staking,
        staking,
        Distributor,
        distributor,
        Mock,
        mock,
        Bond,
        bond,
        deployer,
        owner,
        WETHAddress,
        weth,
        lpAddress,
        lp;

    async function addTime(time) {
        await network.provider.send("evm_increaseTime", [time]);
        await network.provider.send("evm_mine");
    }

    beforeEach(async () => {
        [deployer, owner] = await ethers.getSigners();

        const EIGHT_HOURS = "28800";
        const ONE_DAY = "86400";

        routerAddress = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";
        router = await ethers.getContractAt("contracts/interface/IUniswapV2Router02.sol:IUniswapV2Router02", routerAddress)

        WETHAddress = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
        weth = await ethers.getContractAt("contracts/interface/IWETH.sol:IWETH", WETHAddress);

        VETH = await ethers.getContractFactory("VectorETH");
        vETH = await VETH.deploy();

        VEC = await ethers.getContractFactory("Vector");
        vec = await VEC.deploy();

        lpAddress = await vec.uniswapV2Pair();
        lp = await ethers.getContractAt("contracts/interface/IERC20.sol:IERC20", lpAddress);

        Treasury = await ethers.getContractFactory("VectorTreasury");
        treasury = await Treasury.deploy(vec.getAddress(), vETH.getAddress());

        SVEC = await ethers.getContractFactory("sVEC");
        sVEC = await SVEC.deploy();

        Staking = await ethers.getContractFactory("VECStaking");
        staking = await Staking.deploy(vec.getAddress(), sVEC.getAddress(), EIGHT_HOURS, ONE_DAY);

        Distributor = await ethers.getContractFactory("Distributor");
        distributor = await Distributor.deploy(
            treasury.getAddress(),
            vec.getAddress(),
            vETH.getAddress(),
            staking.getAddress(),
            vETH.getAddress()
        );

        await vec.initialize(treasury.getAddress(), distributor.getAddress(), vETH.getAddress());
        await vec.approve(routerAddress, ethers.parseEther("10000000"));
        await vec.enableTrading();

        await router.addLiquidityETH(vec.getAddress(), "1000000000000000", "0", "0", deployer.address, "100000000000000", {value: ethers.parseEther("50")});

        await treasury.addApprovedMinter(distributor.getAddress());

        await sVEC.setIndex("1000000000");
        await sVEC.initialize(staking.getAddress());

        await staking.setDistributor(distributor.getAddress());
        await distributor.setVECRate("5000");

        Bond = await ethers.getContractFactory("VectorBonding");
        bond = await Bond.deploy(treasury.getAddress(), vETH.getAddress(), WETHAddress, false);

        await bond.setFeeAndFeeTo(owner.getAddress(), "50000");

        await treasury.addApprovedMinter(bond.getAddress());

        await weth.approve(bond.getAddress(), "100000000000000000000000");
        await weth.approve(vETH.getAddress(), "100000000000000000000000");
        await weth.deposit({ value: ethers.parseEther("250.0") });

        await addTime(500);

        await vETH.connect(deployer).addRestakedLST(WETHAddress, ethers.parseEther("1.0"));
        await vETH
            .connect(deployer)
            .deposit(WETHAddress, treasury.getAddress(), ethers.parseEther("25.0"));

        await bond.setBondTerms("0", "604800");

        await vETH.openDeposits();

        await bond.initializeBond(
            "200000",
            "604800",
            "0",
            "25",
            "100000000000",
            "60000000000",
            "2"
        );
    });

    describe("test", () => {
        it("allow bond", async () => {
            console.log(await treasury.valueOfToken(WETHAddress, ethers.parseEther("10.0")));
            console.log(await bond.bondPrice());
            console.log(await bond.debtRatio());
            console.log(await bond.payoutFor("10000000000000000000"));

            await bond.deposit("10000000000000000000", "20000000000000000", [0,0,0]);

            console.log(await bond.bondPrice());
        });

        it("SHOULD BOND", async () => {
            let totalTimePassed = 0;
            let bonds = 1;

            async function payout() {
                while (totalTimePassed < 2592000) {
                    console.log(
                        "Bond Price Before Bond (" +
                            +bonds +
                            "): " +
                            (await bond.bondPrice()).toString()
                    );

                    await bond.deposit("10000000000000000000", "20000000000000000", [0,0,0]);
                    console.log("Debt Ratio: " + await bond.debtRatio());

                    console.log(
                        "Bond Price After Bond (" +
                            +bonds +
                            "): " +
                            (await bond.bondPrice()).toString()
                    );
                    console.log();

                    /// 24 HOURS ///
                    let timePassed = 86400;
                    await addTime(86400);
                    console.log("Debt Ratio: " + await bond.debtRatio());

                    while ((await bond.bondPrice()) > "10500000000000000") {
                        await addTime(60);
                        timePassed = timePassed + 60;
                    }
                    totalTimePassed = totalTimePassed + timePassed;

                    console.log(
                        "Time Passed (Bonds purchased " + (+bonds + +1) + "): " + timePassed
                    );
                    console.log(
                        "Bond Payout (" +
                            (+bonds + +1) +
                            "): " +
                            (await bond.payoutFor("10000000000000000000")).toString()
                    );
                    console.log(totalTimePassed);
                    bonds++;
                }

                console.log("Total ETH Collected " + (await bond.totalPrincipalBonded()));
                console.log("Total LP Collected " + (await lp.balanceOf(await treasury.getAddress())));
                console.log("Total VEC PAYED " + (await bond.totalPayoutGiven()));
                console.log("Total ETH FEES PAYED " + (await weth.balanceOf(owner.address)));
            }

            await payout();
        });
    });
});
