const { ethers } = require("hardhat");
const { expect } = require("chai");

describe("Investor Vesting", () => {
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
        vester1,
        vester2,
        vester3,
        vester4,
        vester5,
        WETHAddress,
        weth,
        lpAddress,
        lp,
        EIGHT_HOURS,
        ONE_DAY,
        ONE_WEEK,
        ONE_YEAR,
        ONE_THOUSAND_VEC,
        FIFTY_THOUSAND_VEC,
        ONE_HUNDRED_THOUSAND_VEC;

    async function addTime(time) {
        await network.provider.send("evm_increaseTime", [time]);
        await network.provider.send("evm_mine");
    }

    beforeEach(async () => {
        [deployer, owner, vester1, vester2, vester3, vester4, vester5] =
            await ethers.getSigners();

        EIGHT_HOURS = "28800";
        ONE_DAY = "86400";
        ONE_WEEK = "604800";
        ONE_YEAR = "31536000";

        ONE_THOUSAND_VEC = "1000000000000";
        FIFTY_THOUSAND_VEC = "50000000000000";
        ONE_HUNDRED_THOUSAND_VEC = "100000000000000";

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

        Vesting = await ethers.getContractFactory("InvestorVectorVest");
        vest = await Vesting.deploy(vec.getAddress(), sVEC.getAddress(), staking.getAddress());

        await weth.deposit({ value: ethers.parseEther("50.0") });
        await weth.approve(vETH.getAddress(), ethers.parseEther("10000.0"));

        await vETH.connect(deployer).addRestakedLST(WETHAddress, ethers.parseEther("0.9"));
        await vec.connect(deployer).approve(vest.getAddress(), ethers.parseEther("100000.0"));
        await vETH
            .connect(deployer)
            .deposit(WETHAddress, treasury.getAddress(), ethers.parseEther("25.0"));

        await vETH
            .connect(deployer)
            .deposit(WETHAddress, vester1.address, ethers.parseEther("25.0"));
    });

    describe("claim()", () => {
        it("NOT allow claim if vesting not set", async () => {
            await expect(
                vest.connect(vester1).claim(vester1.address, ethers.parseEther("1.0"))
            ).to.be.revertedWith("Claim more than vested");
        });

        it("should NOT allow to claim more than redeemable", async () => {
            await vest.setTerms(vester1.address, ONE_HUNDRED_THOUSAND_VEC, ONE_YEAR);

            await addTime(604800);

            const ONE_WEEK_REEDEMABLE_FOR = await vest.redeemableFor(vester1.address);

            const MORE_THAN_ONE_WEEK_REEDEMABLE = Number(ONE_WEEK_REEDEMABLE_FOR) + 1000000000;

            await expect(
                vest.connect(vester1).claim(vester1.address, MORE_THAN_ONE_WEEK_REEDEMABLE)
            ).to.be.revertedWith("Claim more than vested");
        });

        it("should claim properly", async () => {
            await vest.setTerms(vester1.address, ONE_HUNDRED_THOUSAND_VEC, ONE_YEAR);
            await addTime(604800);

            const balanceBefore = await sVEC.balanceOf(vester1.address);

            await vest.connect(vester1).claim(vester1.address, ONE_THOUSAND_VEC);

            const termsAfter = await vest.terms(vester1.address);
            const balanceAfter = await sVEC.balanceOf(vester1.address);

            expect(termsAfter.indexAdjustedClaimed).to.equal(ONE_THOUSAND_VEC);
            expect(balanceBefore).to.equal("0");
            expect(balanceAfter).to.equal(ONE_THOUSAND_VEC);
        });
    });

    describe("percentVested()", () => {
        it("return proper total vesting after one year", async () => {
            await vest.setTerms(vester1.address, ONE_HUNDRED_THOUSAND_VEC, ONE_YEAR);

            await addTime(31536001);

            const percentVestedAfterOneYear = await vest.percentVested(vester1.address);

            expect(percentVestedAfterOneYear).to.equal("1000000000");
        });

        it("shound return proper vesting after a week", async () => {
            await vest.setTerms(vester1.address, ONE_HUNDRED_THOUSAND_VEC, ONE_YEAR);

            await addTime(604800);

            const ONE_WEEK_VESTED = await vest.percentVested(vester1.address);
            const EXPECTED_WEEK_VEST = (1000000000 * ONE_WEEK) / ONE_YEAR;

            expect(ONE_WEEK_VESTED).to.equal(Math.floor(EXPECTED_WEEK_VEST));
        });
    });

    describe("redeemableFor()", () => {
        it("should return full redeemable for after one year", async () => {
            await vest.setTerms(vester1.address, ONE_HUNDRED_THOUSAND_VEC, ONE_YEAR);

            await addTime(31537000);

            const amountRedeemableFor = await vest.redeemableFor(vester1.address);

            expect(amountRedeemableFor).to.equal(ONE_HUNDRED_THOUSAND_VEC);
        });

        it("should return proper redeemable for after a week", async () => {
            await vest.setTerms(vester1.address, ONE_HUNDRED_THOUSAND_VEC, ONE_YEAR);

            await addTime(604800);

            const ONE_WEEK_REEDEMABLE_FOR = await vest.redeemableFor(vester1.address);

            const terms = await vest.terms(vester1.address);
            const EXPECTED_WEEK_VEST = Math.floor(Math.floor(1000000000 * ONE_WEEK) / ONE_YEAR);
            const EXPECT_WEEK_REEDEMABLE_FOR =
                (Number(terms.totalIndexAdjustedCanClaim) * Math.floor(EXPECTED_WEEK_VEST)) / 1000000000;

            expect(ONE_WEEK_REEDEMABLE_FOR).to.equal(Math.floor(EXPECT_WEEK_REEDEMABLE_FOR));
        });
    });

    describe("claimed()", () => {
        it("return 0 claimed upon setting", async () => {
            const termsBefore = await vest.terms(vester1.address);
            await vest.setTerms(vester1.address, ONE_HUNDRED_THOUSAND_VEC, ONE_YEAR);
            const termsAfter = await vest.terms(vester1.address);

            expect(termsBefore.indexAdjustedClaimed).to.equal("0");
            expect(termsAfter.indexAdjustedClaimed).to.equal("0");
        });

        it("should return proper claimed after claiming or staking", async () => {

            await vest.setTerms(vester1.address, ONE_HUNDRED_THOUSAND_VEC, ONE_YEAR);
            await addTime(1209600);

            await vest.connect(vester1).claim(vester1.address, ONE_THOUSAND_VEC);

            expect(await vest.claimed(vester1.address)).to.equal(ONE_THOUSAND_VEC);

            await vest.connect(vester1).claim(vester1.address, ONE_THOUSAND_VEC);

            expect(await vest.claimed(vester1.address)).to.equal(+ONE_THOUSAND_VEC + +ONE_THOUSAND_VEC);
        });

        it("should be index adjusted", async () => {
            console.log(await sVEC.balanceOf(await vest.getAddress()))
            await vest
                .connect(deployer)
                .setTerms(vester1.address, ONE_HUNDRED_THOUSAND_VEC, ONE_YEAR);
            await addTime(604800);
            console.log(await sVEC.balanceOf(await vest.getAddress()))

            await vest.connect(vester1).claim(vester1.address, ONE_THOUSAND_VEC);

            expect(await vest.claimed(vester1.address)).to.equal(ONE_THOUSAND_VEC);

            await staking.rebase();
            await staking.rebase();
            await staking.rebase();
            await staking.rebase();

            const ACTUAL_CLAIMED = await vest.claimed(vester1.address);
            const ACTUAL_BALANCE = await sVEC.balanceOf(vester1.address);

            expect(await vest.toIndexAdjusted(ACTUAL_CLAIMED)).to.equal(ONE_THOUSAND_VEC);
            expect(await vest.toIndexAdjusted(ACTUAL_BALANCE)).to.equal(ONE_THOUSAND_VEC);
            expect(ACTUAL_CLAIMED).to.equal(ACTUAL_BALANCE);
        });
    });

    describe("setTerms()", () => {
        it("NOT set terms if not owner", async () => {
            await expect(
                vest.connect(vester1).setTerms(vester1.address, "10000", ONE_YEAR)
            ).to.be.revertedWith("Ownable: caller is not the owner");
        });

        it("NOT set terms if address already exist", async () => {
            await vest.connect(deployer).setTerms(vester1.address, "10000", ONE_YEAR);
            await expect(
                vest.connect(deployer).setTerms(vester1.address, "15000", ONE_YEAR)
            ).to.be.revertedWith("Address already exists");
        });

        it("set terms properly", async () => {
            const termsBefore = await vest.terms(vester1.address);
            await vest
                .connect(deployer)
                .setTerms(vester1.address, ONE_HUNDRED_THOUSAND_VEC, ONE_YEAR);
            const termsAfter = await vest.terms(vester1.address);

            expect(termsBefore.totalIndexAdjustedCanClaim).to.equal("0");

            expect(termsAfter.totalIndexAdjustedCanClaim).to.equal(ONE_HUNDRED_THOUSAND_VEC);
            expect(termsAfter.indexAdjustedClaimed).to.equal("0");
            expect(termsAfter.vestLength).to.equal(ONE_YEAR);
        });
    });
});
