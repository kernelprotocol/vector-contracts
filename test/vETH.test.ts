const { ethers } = require("hardhat");
const { expect } = require("chai");

describe("vETH", () => {
    let owner: { address: any },
        user: { address: any },
        approvedManager: { address: any },
        mockRoute: { address: any },
        MockWETH,
        mockWETH: {
            transfer(arg0: any, arg1: any): unknown;
            deposit: (arg0: { value: any }) => any;
            approve: (arg0: any, arg1: any) => any;
            getAddress: () => any;
            balanceOf: (arg0: any) => any;
        },
        mockLST: {
            deposit: (arg0: { value: any }) => any;
            approve: (arg0: any, arg1: any) => any;
            getAddress: () => any;
        },
        mockLST2: {
            deposit: (arg0: { value: any }) => any;
            approve: (arg0: any, arg1: any) => any;
            getAddress: () => any;
        },
        VEC,
        vec: { getAddress: () => any; initialize: (arg0: any, arg1: any, arg2: any) => any },
        VETH,
        vETH: {
            addApprovedManager(address: any): unknown;
            currentBalance(arg0: any): any;
            updateDeposit(arg0: any): unknown;
            approvedRestakedLSTs(arg0: string): any;
            setRedemtionActive(): unknown;
            updateRouteRestakedLSTTo(arg0: any, address: any): unknown;
            getAddress: () => any;
            connect: (arg0: any) => {
                manageRestakedLST(arg0: any, address: any, arg2: any): unknown;
                addRestakedLST(arg0: any, arg1: any): any;
                removeRestakedLST(arg0: any): any;
                redeem(arg0: any, address: any, arg2: string): any;
                (): any;
                new (): any;
                deposit: { (arg0: any, arg1: any, arg2: string): any; new (): any };
            };
            addRestakedLST: (arg0: any, arg1: any) => any;
            balanceOf: (arg0: any) => any;
            totalSupply: () => any;
            restakedLSTManaged: (arg0: any) => any;
            totalRestakedLSTDeposited: (arg0: any) => any;
        },
        Treasury,
        treasury,
        SVEC,
        sVEC,
        Staking,
        staking,
        Distributor,
        distributor;

    beforeEach(async () => {
        [owner, user, mockRoute, approvedManager] = await ethers.getSigners();

        const EIGHT_HOURS = "28800";
        const ONE_DAY = "86400";

        MockWETH = await ethers.getContractFactory("MockWETH");
        mockWETH = await MockWETH.deploy();
        mockLST = await MockWETH.deploy();
        mockLST2 = await MockWETH.deploy();

        VEC = await ethers.getContractFactory("Vector");
        vec = await VEC.deploy();

        VETH = await ethers.getContractFactory("VectorETH");
        vETH = await VETH.deploy();

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
        await treasury.addApprovedMinter(distributor.getAddress());

        await sVEC.setIndex("1000000000");
        await sVEC.initialize(staking.getAddress());

        await staking.setDistributor(distributor.getAddress());
        await distributor.setVECRate("5000");

        await mockWETH.deposit({ value: ethers.parseEther("10.0") });
        await mockWETH.approve(vETH.getAddress(), ethers.parseEther("10.0"));

        await mockWETH.connect(user).deposit({ value: ethers.parseEther("10.0") });
        await mockWETH.connect(user).approve(vETH.getAddress(), ethers.parseEther("10.0"));

        await mockLST.deposit({ value: ethers.parseEther("10.0") });
        await mockLST.approve(vETH.getAddress(), ethers.parseEther("10.0"));
        await mockLST2.deposit({ value: ethers.parseEther("10.0") });
        await mockLST2.approve(vETH.getAddress(), ethers.parseEther("10.0"));

        await vETH.addApprovedManager(approvedManager.address);
    });

    describe("deposit()", () => {
        it("should NOT allow non owner to deposit if deposits not opened", async () => {
            await expect(
                vETH
                    .connect(user)
                    .deposit(mockWETH.getAddress(), owner.address, ethers.parseEther("1.0"))
            ).to.be.revertedWith("Deposits not open");
        });

        it("Should NOT deposit if not approved token", async () => {
            await expect(
                vETH
                    .connect(owner)
                    .deposit(mockWETH.getAddress(), owner.address, ethers.parseEther("1.0"))
            ).to.be.revertedWith("Not approved restaked LST");
        });

        it("Should NOT deposit if amount is 0", async () => {
            await vETH.addRestakedLST(mockWETH.getAddress(), ethers.parseEther("0.9"));
            await expect(
                vETH.connect(owner).deposit(mockWETH.getAddress(), owner.address, "0")
            ).to.be.revertedWith("Can not deposit 0");
        });

        it("Should allow deposit of owner before deposits opened", async () => {
            await vETH.addRestakedLST(mockWETH.getAddress(), ethers.parseEther("0.9"));
            await vETH
                .connect(owner)
                .deposit(mockWETH.getAddress(), owner.address, ethers.parseEther("1.0"));
        });

        it("should allow deposits of users once deoposits opened", async () => {
            await vETH.addRestakedLST(mockWETH.getAddress(), ethers.parseEther("0.9"));
            await vETH.connect(owner).openDeposits();

            await vETH
                .connect(user)
                .deposit(mockWETH.getAddress(), owner.address, ethers.parseEther("1.0"));
        });

        it("Should deposit properly when not routing", async () => {
            await vETH.addRestakedLST(mockWETH.getAddress(), ethers.parseEther("0.9"));
            await vETH
                .connect(owner)
                .deposit(mockWETH.getAddress(), owner.address, ethers.parseEther("1.0"));

            expect(await vETH.balanceOf(owner.address)).to.equal(ethers.parseEther("0.9"));
            expect(await vETH.totalSupply()).to.equal(ethers.parseEther("0.9"));
            expect(await vETH.restakedLSTManaged(mockWETH.getAddress())).to.equal("0");
            expect(await vETH.totalRestakedLSTDeposited(mockWETH.getAddress())).to.equal(
                ethers.parseEther("1.0")
            );
            expect(await mockWETH.balanceOf(vETH.getAddress())).to.equal(ethers.parseEther("1.0"));
        });

        it("Should deposit properly when routing", async () => {
            await vETH.addRestakedLST(mockWETH.getAddress(), ethers.parseEther("0.9"));
            await vETH.updateRouteRestakedLSTTo(mockWETH.getAddress(), mockRoute.address);

            await vETH
                .connect(owner)
                .deposit(mockWETH.getAddress(), owner.address, ethers.parseEther("1.0"));

            expect(await vETH.balanceOf(owner.address)).to.equal(ethers.parseEther("0.9"));
            expect(await vETH.totalSupply()).to.equal(ethers.parseEther("0.9"));
            expect(await vETH.restakedLSTManaged(mockWETH.getAddress())).to.equal(
                ethers.parseEther("1.0")
            );
            expect(await vETH.totalRestakedLSTDeposited(mockWETH.getAddress())).to.equal(
                ethers.parseEther("1.0")
            );
            expect(await mockWETH.balanceOf(vETH.getAddress())).to.equal("0");
            expect(await mockWETH.balanceOf(mockRoute.address)).to.equal(ethers.parseEther("1.0"));
        });
    });

    describe("redeem()", () => {
        it("should NOT redeem when reedemtions are not active", async () => {
            await expect(
                vETH.connect(owner).redeem(mockWETH.getAddress(), owner.address, "0")
            ).to.be.revertedWith("Redemtions not active");
        });

        it("should NOT redeem if not approved", async () => {
            await vETH.setRedemtionActive();
            await expect(
                vETH.connect(owner).redeem(vec.getAddress(), owner.address, "0")
            ).to.be.revertedWith("Not restaked LST");
        });

        it("should NOT redeem if not enough vETH", async () => {
            await vETH.addRestakedLST(mockWETH.getAddress(), ethers.parseEther("0.9"));
            await vETH
                .connect(owner)
                .deposit(mockWETH.getAddress(), owner.address, ethers.parseEther("1.0"));
            await vETH.setRedemtionActive();

            await expect(
                vETH
                    .connect(owner)
                    .redeem(mockWETH.getAddress(), owner.address, ethers.parseEther("1.1"))
            ).to.be.reverted;
        });

        it("should redeem properly", async () => {
            await vETH.addRestakedLST(mockWETH.getAddress(), ethers.parseEther("0.9"));
            await vETH
                .connect(owner)
                .deposit(mockWETH.getAddress(), owner.address, ethers.parseEther("1.0"));
            await vETH.setRedemtionActive();

            await vETH
                .connect(owner)
                .redeem(mockWETH.getAddress(), owner.address, ethers.parseEther("0.45"));

            expect(await vETH.balanceOf(owner.address)).to.equal(ethers.parseEther("0.45"));
            expect(await vETH.totalSupply()).to.equal(ethers.parseEther("0.45"));
            expect(await vETH.restakedLSTManaged(mockWETH.getAddress())).to.equal("0");
            expect(await vETH.totalRestakedLSTDeposited(mockWETH.getAddress())).to.equal(
                ethers.parseEther("0.5")
            );
            expect(await mockWETH.balanceOf(vETH.getAddress())).to.equal(ethers.parseEther("0.5"));
        });
    });

    describe("updateDeposit()", () => {
        it("should update properly when none has been managed", async () => {
            await vETH.addRestakedLST(mockWETH.getAddress(), ethers.parseEther("0.9"));
            await vETH
                .connect(owner)
                .deposit(mockWETH.getAddress(), owner.address, ethers.parseEther("1.0"));

            await mockWETH.transfer(vETH.getAddress(), ethers.parseEther("0.5"));

            expect(await vETH.totalRestakedLSTDeposited(mockWETH.getAddress())).to.equal(
                ethers.parseEther("1.0")
            );

            expect(await vETH.currentBalance(mockWETH.getAddress())).to.equal(
                ethers.parseEther("1.5")
            );

            await vETH.updateDeposit(mockWETH.getAddress());

            expect(await vETH.totalRestakedLSTDeposited(mockWETH.getAddress())).to.equal(
                ethers.parseEther("1.5")
            );
            expect(await vETH.currentBalance(mockWETH.getAddress())).to.equal(
                ethers.parseEther("1.5")
            );
        });

        it("should update properly when there has been managed", async () => {
            await vETH.addRestakedLST(mockWETH.getAddress(), ethers.parseEther("0.9"));
            await vETH
                .connect(owner)
                .deposit(mockWETH.getAddress(), owner.address, ethers.parseEther("1.0"));

            await vETH
                .connect(approvedManager)
                .manageRestakedLST(mockWETH.getAddress(), user.address, ethers.parseEther("1.0"));
            await mockWETH.transfer(vETH.getAddress(), ethers.parseEther("0.5"));

            expect(await vETH.totalRestakedLSTDeposited(mockWETH.getAddress())).to.equal(
                ethers.parseEther("1.0")
            );

            expect(await vETH.currentBalance(mockWETH.getAddress())).to.equal(
                ethers.parseEther("1.5")
            );

            await vETH.updateDeposit(mockWETH.getAddress());

            expect(await vETH.totalRestakedLSTDeposited(mockWETH.getAddress())).to.equal(
                ethers.parseEther("1.5")
            );
            expect(await vETH.currentBalance(mockWETH.getAddress())).to.equal(
                ethers.parseEther("1.5")
            );
        });
    });

    describe("addRestakedLST()", () => {
        it("should NOT allow non owner to add", async () => {
            await expect(
                vETH.connect(user).addRestakedLST(mockWETH.getAddress(), ethers.parseEther("0.9"))
            ).to.be.revertedWith("Ownable: caller is not the owner");
        });

        it("should NOT allow to be added twice", async () => {
            await vETH.addRestakedLST(mockWETH.getAddress(), ethers.parseEther("0.9"));
            await expect(
                vETH.connect(owner).addRestakedLST(mockWETH.getAddress(), ethers.parseEther("0.9"))
            ).to.be.revertedWith("Already added");
        });

        it("should add properly", async () => {
            await vETH
                .connect(owner)
                .addRestakedLST(mockWETH.getAddress(), ethers.parseEther("0.9"));
            await vETH
                .connect(owner)
                .addRestakedLST(mockLST.getAddress(), ethers.parseEther("1.0"));

            expect(await vETH.approvedRestakedLSTs("0")).to.equal(await mockWETH.getAddress());
            expect(await vETH.approvedRestakedLSTs("1")).to.equal(await mockLST.getAddress());
        });
    });

    describe("removeRestakedLST()", () => {
        it("should NOT allow non owner to remove", async () => {
            await expect(
                vETH.connect(user).removeRestakedLST(mockWETH.getAddress())
            ).to.be.revertedWith("Ownable: caller is not the owner");
        });

        it("should NOT allow to remove unadded token", async () => {
            await expect(
                vETH.connect(owner).removeRestakedLST(mockWETH.getAddress())
            ).to.be.revertedWith("Not restaked LST");
        });

        it("should remove properly", async () => {
            await vETH
                .connect(owner)
                .addRestakedLST(mockWETH.getAddress(), ethers.parseEther("0.9"));
            await vETH
                .connect(owner)
                .addRestakedLST(mockLST.getAddress(), ethers.parseEther("1.0"));
            await vETH
                .connect(owner)
                .addRestakedLST(mockLST2.getAddress(), ethers.parseEther("1.1"));

            expect(await vETH.approvedRestakedLSTs("0")).to.equal(await mockWETH.getAddress());
            expect(await vETH.approvedRestakedLSTs("1")).to.equal(await mockLST.getAddress());
            expect(await vETH.approvedRestakedLSTs("2")).to.equal(await mockLST2.getAddress());

            await vETH.connect(owner).removeRestakedLST(await mockLST.getAddress());

            expect(await vETH.approvedRestakedLSTs("0")).to.equal(await mockWETH.getAddress());
            expect(await vETH.approvedRestakedLSTs("1")).to.equal(await mockLST2.getAddress());
        });
    });

    describe("manageRestakedLST()", () => {
        it("should NOT allow non approved managed to manage", async () => {
            await expect(
                vETH
                    .connect(owner)
                    .manageRestakedLST(
                        mockWETH.getAddress(),
                        owner.address,
                        ethers.parseEther("0.9")
                    )
            ).to.be.revertedWith("Not approved manager");
        });

        it("should NOT allow non approved token to be managed", async () => {
            await expect(
                vETH
                    .connect(approvedManager)
                    .manageRestakedLST(
                        mockWETH.getAddress(),
                        owner.address,
                        ethers.parseEther("0.9")
                    )
            ).to.be.revertedWith("Not restaked LST");
        });

        it("should manage properly", async () => {
            await vETH.addRestakedLST(mockWETH.getAddress(), ethers.parseEther("0.9"));
            await vETH
                .connect(owner)
                .deposit(mockWETH.getAddress(), owner.address, ethers.parseEther("1.0"));

            expect(await vETH.restakedLSTManaged(mockWETH.getAddress())).to.equal("0");

            await vETH
                .connect(approvedManager)
                .manageRestakedLST(
                    mockWETH.getAddress(),
                    approvedManager.address,
                    ethers.parseEther("1.0")
                );

            expect(await vETH.restakedLSTManaged(mockWETH.getAddress())).to.equal(
                ethers.parseEther("1.0")
            );
            expect(await vETH.currentBalance(mockWETH.getAddress())).to.equal(
                ethers.parseEther("1.0")
            );
        });
    });

    describe("addMangedRestakedLST()", () => {
        it("should NOT allow non approved managed to add", async () => {
            await expect(
                vETH
                    .connect(owner)
                    .addMangedRestakedLST(mockWETH.getAddress(), ethers.parseEther("0.9"))
            ).to.be.revertedWith("Not approved manager");
        });

        it("should NOT allow non approved token to add", async () => {
            await expect(
                vETH
                    .connect(approvedManager)
                    .addMangedRestakedLST(mockWETH.getAddress(), ethers.parseEther("0.9"))
            ).to.be.revertedWith("Not restaked LST");
        });

        it("should re add managed properly", async () => {
            await mockWETH.connect(approvedManager).deposit({ value: ethers.parseEther("10.0") });
            await mockWETH
                .connect(approvedManager)
                .approve(vETH.getAddress(), ethers.parseEther("10.0"));

            await vETH.addRestakedLST(mockWETH.getAddress(), ethers.parseEther("0.9"));
            await vETH
                .connect(owner)
                .deposit(mockWETH.getAddress(), owner.address, ethers.parseEther("1.0"));

            expect(await vETH.restakedLSTManaged(mockWETH.getAddress())).to.equal("0");

            await vETH
                .connect(approvedManager)
                .manageRestakedLST(
                    mockWETH.getAddress(),
                    approvedManager.address,
                    ethers.parseEther("1.0")
                );

            expect(await vETH.restakedLSTManaged(mockWETH.getAddress())).to.equal(
                ethers.parseEther("1.0")
            );
            expect(await vETH.currentBalance(mockWETH.getAddress())).to.equal(
                ethers.parseEther("1.0")
            );

            await vETH
                .connect(approvedManager)
                .addMangedRestakedLST(mockWETH.getAddress(), ethers.parseEther("1.5"));

            expect(await vETH.restakedLSTManaged(mockWETH.getAddress())).to.equal("0");
            expect(await vETH.currentBalance(mockWETH.getAddress())).to.equal(
                ethers.parseEther("1.5")
            );
        });
    });
});
