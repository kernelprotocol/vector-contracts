const { ethers } = require("hardhat");
const { expect } = require("chai");

describe("Vector Vesting", () => {
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
        Vesting,
        vest,
        deployer,
        owner,
        vester,
        WETHAddress,
        weth,
        lpAddress,
        lp,
        EIGHT_HOURS,
        ONE_DAY,
        ONE_WEEK,
        ONE_YEAR;

    async function addTime(time) {
        await network.provider.send("evm_increaseTime", [time]);
        await network.provider.send("evm_mine");
    }

    beforeEach(async () => {
        [deployer, owner, vester] = await ethers.getSigners();

        EIGHT_HOURS = "28800";
        ONE_DAY = "86400";
        ONE_WEEK = "604800";
        ONE_YEAR = "31536000";

        routerAddress = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";
        router = await ethers.getContractAt(
            "contracts/interface/IUniswapV2Router02.sol:IUniswapV2Router02",
            routerAddress
        );

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
            vETH.getAddress(),
            staking.getAddress()
        );

        await vec.initialize(treasury.getAddress(), distributor.getAddress(), vETH.getAddress());
        await vec.approve(routerAddress, ethers.parseEther("10000000"));
        await vec.enableTrading();

        await router.addLiquidityETH(
            vec.getAddress(),
            "1000000000000000",
            "0",
            "0",
            deployer.address,
            "100000000000000",
            { value: ethers.parseEther("50") }
        );

        await treasury.addApprovedMinter(distributor.getAddress());

        await sVEC.setIndex("1000000000");
        await sVEC.initialize(staking.getAddress());

        await staking.setDistributor(distributor.getAddress());
        await distributor.setVECRate("5000");

        Vesting = await ethers.getContractFactory("VectorVest");
        vest = await Vesting.deploy(
            vec.getAddress(),
            vETH.getAddress(),
            treasury.getAddress(),
            staking.getAddress()
        );

        await treasury.addApprovedMinter(vest.getAddress());

        await weth.deposit({ value: ethers.parseEther("50.0") });
        await weth.approve(vETH.getAddress(), ethers.parseEther("10000.0"));

        await vETH.openDeposits();

        await vETH.connect(deployer).addRestakedLST(WETHAddress, ethers.parseEther("0.9"));
        await vETH.connect(vester).approve(vest.getAddress(), ethers.parseEther("1000.0"));
        await vETH
            .connect(deployer)
            .deposit(WETHAddress, treasury.getAddress(), ethers.parseEther("25.0"));

        await vETH
            .connect(deployer)
            .deposit(WETHAddress, vester.address, ethers.parseEther("25.0"));
    });

    describe("claim()", () => {
        it("NOT allow claim if vesting not set", async () => {
            await expect(
                vest.connect(vester).claim(vester.address, ethers.parseEther("1.0"))
            ).to.be.revertedWith("Claim more than vested");
        });

        it("should NOT allow to claim more than redeemable", async () => {
            await vest.connect(deployer).setTerms(vester.address, "10000");

            await addTime(604800);

            const ONE_WEEK_REEDEMABLE_FOR = await vest.redeemableFor(vester.address);

            const RESERVE_BACKING = await treasury.RESERVE_BACKING();

            const REEDEMABLE_IN_VETH =
                (Number(ONE_WEEK_REEDEMABLE_FOR) / 1000000000) * Number(RESERVE_BACKING);

            const MORE_THAN_ONE_WEEK_REEDEMABLE = REEDEMABLE_IN_VETH + Number(RESERVE_BACKING);

            await expect(
                vest.connect(vester).claim(vester.address, MORE_THAN_ONE_WEEK_REEDEMABLE)
            ).to.be.revertedWith("Claim more than vested");
        });

        it("should claim properly", async () => {
            await vest.connect(deployer).setTerms(vester.address, "10000");
            await addTime(604800);

            const RESERVE_BACKING = await treasury.RESERVE_BACKING();
            const balanceBefore = await vec.balanceOf(vester.address);

            await vest.connect(vester).claim(vester.address, RESERVE_BACKING);

            const termsAfter = await vest.terms(vester.address);
            const balanceAfter = await vec.balanceOf(vester.address);

            expect(termsAfter.indexClaimed).to.equal("1000000000");
            expect(balanceBefore).to.equal("0");
            expect(balanceAfter).to.equal("1000000000");
        });
    });

    describe("stake()", () => {
        it("NOT allow stake if vesting not set", async () => {
            await expect(
                vest.connect(vester).stake(vester.address, ethers.parseEther("1.0"))
            ).to.be.revertedWith("Claim more than vested");
        });

        it("should NOT allow to stake more than redeemable", async () => {
            await vest.connect(deployer).setTerms(vester.address, "10000");

            await addTime(604800);

            const ONE_WEEK_REEDEMABLE_FOR = await vest.redeemableFor(vester.address);

            const RESERVE_BACKING = await treasury.RESERVE_BACKING();

            const REEDEMABLE_IN_VETH =
                (Number(ONE_WEEK_REEDEMABLE_FOR) / 1000000000) * Number(RESERVE_BACKING);

            const MORE_THAN_ONE_WEEK_REEDEMABLE = REEDEMABLE_IN_VETH + Number(RESERVE_BACKING);

            await expect(
                vest.connect(vester).stake(vester.address, MORE_THAN_ONE_WEEK_REEDEMABLE)
            ).to.be.revertedWith("Claim more than vested");
        });

        it("should stake properly", async () => {
            await vest.connect(deployer).setTerms(vester.address, "10000");
            await addTime(604800);

            const RESERVE_BACKING = await treasury.RESERVE_BACKING();
            const balanceBefore = await sVEC.balanceOf(vester.address);

            await vest.connect(vester).stake(vester.address, RESERVE_BACKING);

            const termsAfter = await vest.terms(vester.address);
            const balanceAfter = await sVEC.balanceOf(vester.address);

            expect(termsAfter.indexClaimed).to.equal("1000000000");
            expect(balanceBefore).to.equal("0");
            expect(balanceAfter).to.equal("1000000000");
        });
    });

    describe("percentVested()", () => {
        it("return proper total vesting after one year", async () => {
            await vest.connect(deployer).setTerms(vester.address, "10000");

            await addTime(31536001);

            const percentVestedAfterOneYear = await vest.percentVested();

            expect(percentVestedAfterOneYear).to.equal("1000000000");
        });

        it("shound return proper vesting after a week", async () => {
            await vest.connect(deployer).setTerms(vester.address, "10000");
            const VESTING_START = await vest.startVest();

            await addTime(604800);
            const ONE_WEEK_VESTED = await vest.percentVested();


            const blockNum = await ethers.provider.getBlockNumber();
            const block = await ethers.provider.getBlock(blockNum);
            const timestamp = block.timestamp;

            const EXPECTED_WEEK_VEST = (Number(1000000000) * (Number(timestamp) - Number(VESTING_START))) / Number(ONE_YEAR);

            expect(ONE_WEEK_VESTED).to.equal(Math.floor(EXPECTED_WEEK_VEST));
        });
    });

    describe("percentAddressVested()", () => {
        it("return full amount vested for addrss after one year", async () => {
            await vest.connect(deployer).setTerms(vester.address, "10000");

            await addTime(31537000);

            const addressPercentVestedAfterOneYear = await vest.percentAddressVested(
                vester.address
            );

            expect(addressPercentVestedAfterOneYear).to.equal("10000");
        });

        it("shound return proper vesting percent for address after a week", async () => {
            await vest.connect(deployer).setTerms(vester.address, "10000");

            await addTime(604800);

            const ONE_WEEK_ADDRESS_VESTED = await vest.percentAddressVested(vester.address);

            const terms = await vest.terms(vester.address);
            const EXPECTED_WEEK_VEST = (1000000000 * ONE_WEEK) / ONE_YEAR;

            const EXPECT_WEEK_ADDRESS_VEST =
                (Number(terms.percent) * Math.floor(EXPECTED_WEEK_VEST)) / 1000000000;

            expect(ONE_WEEK_ADDRESS_VESTED).to.equal(Math.floor(EXPECT_WEEK_ADDRESS_VEST));
        });
    });

    describe("redeemableFor()", () => {
        it("should return full redeemable for after one year", async () => {
            await vest.connect(deployer).setTerms(vester.address, "10000");

            await addTime(31537000);

            const amountRedeemableFor = await vest.redeemableFor(vester.address);

            // 1% of total supply
            const HUNDRED_THOUSAND = "100000000000000";

            expect(amountRedeemableFor).to.equal(HUNDRED_THOUSAND);
        });

        it("should return proper redeemable for after a week", async () => {
            await vest.connect(deployer).setTerms(vester.address, "10000");

            await addTime(604800);

            const ONE_WEEK_REEDEMABLE_FOR = await vest.redeemableFor(vester.address);

            const terms = await vest.terms(vester.address);
            const EXPECTED_WEEK_VEST = (1000000000 * ONE_WEEK) / ONE_YEAR;
            const EXPECT_WEEK_ADDRESS_VEST =
                (Number(terms.percent) * Math.floor(EXPECTED_WEEK_VEST)) / 1000000000;
            const EXPECT_WEEK_REEDEMABLE_FOR =
                (Number(await vec.totalSupply()) * Math.floor(EXPECT_WEEK_ADDRESS_VEST)) / 1000000;

            expect(ONE_WEEK_REEDEMABLE_FOR).to.equal(Math.floor(EXPECT_WEEK_REEDEMABLE_FOR));
        });

        it("should be redeemable for 0 if more than can claim", async () => {
            await vest.connect(deployer).setTerms(vester.address, "10000");
            await addTime(604800);

            const RESERVE_BACKING = await treasury.RESERVE_BACKING();

            const TO_CLAIM = Number(RESERVE_BACKING) * 3;

            await vest.connect(vester).stake(vester.address, TO_CLAIM);

            await staking.rebase();
            await staking.rebase();

            expect(await vest.redeemableFor(vester.address)).to.equal("0");
        });
    });

    describe("claimed()", () => {
        it("return 0 claimed upon setting", async () => {
            const termsBefore = await vest.terms(vester.address);
            await vest.connect(deployer).setTerms(vester.address, "10000");
            const termsAfter = await vest.terms(vester.address);

            expect(termsBefore.indexClaimed).to.equal("0");
            expect(termsBefore.indexClaimed).to.equal(termsAfter.indexClaimed);
        });

        it("should return proper claimed after claiming or staking", async () => {
            const RESERVE_BACKING = await treasury.RESERVE_BACKING();

            await vest.connect(deployer).setTerms(vester.address, "10000");
            await addTime(604800);

            await vest.connect(vester).stake(vester.address, RESERVE_BACKING);

            expect(await vest.claimed(vester.address)).to.equal("1000000000");

            await vest.connect(vester).claim(vester.address, RESERVE_BACKING);

            expect(await vest.claimed(vester.address)).to.equal("2000000000");
        });

        it("should be index adjusted", async () => {
            await vest.connect(deployer).setTerms(vester.address, "10000");
            await addTime(604800);

            const RESERVE_BACKING = await treasury.RESERVE_BACKING();

            const TO_CLAIM = Number(RESERVE_BACKING) * 3;

            await vest.connect(vester).stake(vester.address, TO_CLAIM);

            expect(await vest.claimed(vester.address)).to.equal(
                (BigInt(TO_CLAIM) * BigInt(ethers.parseEther("1.0"))) /
                    BigInt(RESERVE_BACKING) /
                    BigInt(1000000000)
            );

            await staking.rebase();
            await staking.rebase();

            const ACTUAL_CLAIMED = await vest.claimed(vester.address);

            const INDEX = await staking.index();
            const EXPECTED_CLAIMED = (BigInt(3000000000) * BigInt(INDEX)) / BigInt(1000000000);

            expect(ACTUAL_CLAIMED).to.equal(EXPECTED_CLAIMED);
        });
    });

    describe("setTerms()", () => {
        it("NOT set terms if not owner", async () => {
            await expect(vest.connect(vester).setTerms(vester.address, "10000")).to.be.revertedWith(
                "Ownable: caller is not the owner"
            );
        });

        it("NOT set terms if address already exist", async () => {
            await vest.connect(deployer).setTerms(vester.address, "10000");
            await expect(
                vest.connect(deployer).setTerms(vester.address, "15000")
            ).to.be.revertedWith("Address already exists");
        });

        it("NOT set terms if already allocated over max", async () => {
            await vest.connect(deployer).setTerms(vester.address, "190000");
            await expect(
                vest.connect(deployer).setTerms(owner.address, "11000")
            ).to.be.revertedWith("Cannot allocate more than 20%");
        });

        it("set terms properly", async () => {
            const termsBefore = await vest.terms(vester.address);
            await vest.connect(deployer).setTerms(vester.address, "10000");
            const termsAfter = await vest.terms(vester.address);

            expect(termsBefore.percent).to.equal("0");
            expect(termsAfter.percent).to.equal("10000");
        });

        it("should keep same vest start and vest end after first terms set", async () => {
            await vest.connect(deployer).setTerms(vester.address, "10000");
            const vestEndBefore = await vest.fullVest();
            const vestStartBefore = await vest.startVest();

            await addTime(60000);

            await vest.connect(deployer).setTerms(owner.address, "10000");

            const vestEndAfter = await vest.fullVest();
            const vestStartAfter = await vest.startVest();

            expect(vestEndBefore).to.equal(vestEndAfter);
            expect(vestStartBefore).to.equal(vestStartAfter);
        });
    });
});
