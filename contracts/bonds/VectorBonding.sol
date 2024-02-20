import "../libraries/SafeMath.sol";
import "../libraries/FixedPoint.sol";
import "../libraries/Address.sol";
import "../libraries/SafeERC20.sol";
import "../interface/ITreasury.sol";

pragma experimental ABIEncoderV2;

interface IUniswapV2Router02 {
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function WETH() external pure returns (address);
}

interface IvETH {
    function deposit(
        address _restakedLST,
        address _to,
        uint256 _amount
    ) external;
}

// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.7.5;

contract VectorBonding {
    using FixedPoint for *;
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    enum PARAMETER {
        VESTING,
        PAYOUT,
        DEBT
    }

    enum BondType {
        TAKEINPRINCIPAL,
        WETHTOVETH,
        WETHTOLP
    }

    modifier onlyOwner() {
        require(owner == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    /// EVENTS ///

    event BondCreated(uint256 deposit, uint256 payout, uint256 expires);
    event BondRedeemed(address recipient, uint256 payout, uint256 remaining);
    event BondPriceChanged(uint256 internalPrice, uint256 debtRatio);
    event ControlVariableAdjustment(
        uint256 initialBCV,
        uint256 newBCV,
        uint256 adjustment,
        bool addition
    );

    /// STATE VARIABLES ///

    uint256 public constant FEE_DENOM = 1_000_000;

    address public owner;

    IERC20 public immutable VEC; // token paid for principal
    IERC20 public immutable principalToken; // inflow token
    ITreasury public immutable treasury; // pays for and receives principal
    IUniswapV2Router02 public immutable uniswapV2Router;

    address public LP;
    address public feeTo;
    address public immutable vETH;

    // in ten-thousandths of a %. i.e. 5000 = 0.5%
    uint256 public feePercent;
    uint256 public totalPrincipalBonded;
    uint256 public totalPayoutGiven;
    uint256 public totalDebt; // total value of outstanding bonds; used for pricing
    uint256 public lastDecay; // reference timestamp for debt decay

    Terms public terms; // stores terms for new bonds
    Adjust public adjustment; // stores adjustment to BCV data

    bool public immutable feeInVEC;

    BondType public bondType;

    mapping(address => Bond) public bondInfo; // stores bond information for depositors

    /// STRUCTS ///

    struct MinAmountsLiq {
        uint256 minVECToSwap;
        uint256 minVECToAdd;
        uint256 minWETHToAdd;
    }

    // Info for creating new bonds
    struct Terms {
        uint256 controlVariable; // scaling variable for price
        uint256 vestingTerm; // in seconds
        uint256 minimumPrice; // vs principal value
        uint256 maxPayout; // in thousandths of a %. i.e. 500 = 0.5%
        uint256 maxDebt; // payout token decimal debt ratio, max % total supply created as debt
    }

    // Info for bond holder
    struct Bond {
        uint256 payout; // payout token remaining to be paid
        uint256 vesting; // seconds left to vest
        uint256 lastBlockTimestamp; // Last interaction
        uint256 truePricePaid; // Price paid (principal tokens per payout token) in ten-millionths - 4000000 = 0.4
    }

    // Info for incremental adjustments to control variable
    struct Adjust {
        bool add; // addition or subtraction
        uint256 rate; // increment
        uint256 target; // BCV when adjustment finished
        uint256 buffer; // minimum length (in seconds) between adjustments
        uint256 lastBlockTimestamp; // timestamp when last adjustment made
    }

    /// CONSTRUCTOR ///

    constructor(
        address _treasury,
        address _vETH,
        address _principalToken,
        bool _feeInVEC
    ) {
        treasury = ITreasury(_treasury);
        VEC = IERC20(ITreasury(_treasury).VEC());
        principalToken = IERC20(_principalToken);
        owner = msg.sender;
        feeInVEC = _feeInVEC;
        vETH = _vETH;

        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(
            0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
        );

        uniswapV2Router = _uniswapV2Router;
    }

    /// INITIALIZATION ///

    /**
     *  @notice initializes bond parameters
     *  @param _controlVariable uint256
     *  @param _vestingTerm uint256
     *  @param _minimumPrice uint256
     *  @param _maxPayout uint256
     *  @param _maxDebt uint256
     *  @param _initialDebt uint256
     */
    function initializeBond(
        uint256 _controlVariable,
        uint256 _vestingTerm,
        uint256 _minimumPrice,
        uint256 _maxPayout,
        uint256 _maxDebt,
        uint256 _initialDebt,
        BondType _bondType
    ) external onlyOwner {
        require(currentDebt() == 0, "Debt must be 0 for initialization");
        bondType = _bondType;

        if (_bondType == BondType.WETHTOVETH) {
            require(address(principalToken) == uniswapV2Router.WETH(), "Principal must be WETH");
            principalToken.approve(vETH, type(uint256).max);
        } else if (_bondType == BondType.WETHTOLP) {
            require(address(principalToken) == uniswapV2Router.WETH(), "Principal must be WETH");
            LP = treasury.LP();
            principalToken.approve(address(uniswapV2Router), type(uint256).max);
            VEC.approve(address(uniswapV2Router), type(uint256).max);
        }

        terms = Terms({
            controlVariable: _controlVariable,
            vestingTerm: _vestingTerm,
            minimumPrice: _minimumPrice,
            maxPayout: _maxPayout,
            maxDebt: _maxDebt
        });
        totalDebt = _initialDebt;
        lastDecay = block.timestamp;
    }

    /// POLICY FUNCTIONS ///

    /// @notice Withdraw stuck token from contract
    function withdrawStuckToken(
        address _token,
        address _to,
        uint256 _amount
    ) external onlyOwner {
        require(_token != address(0), "_token address cannot be 0");
        require(_token != address(VEC), "Can not withdraw VEC");
        IERC20(_token).safeTransfer(_to, _amount);
    }

    function setFeeAndFeeTo(
        address _feeTo,
        uint256 _feePercent
    ) external onlyOwner {
        require(_feePercent <= FEE_DENOM, "Fee > FEE_DENOM");
        feeTo = _feeTo;
        feePercent = _feePercent;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(
            newOwner != address(0),
            "Ownable: new owner is the zero address"
        );
        owner = newOwner;
    }

    /**
     *  @notice set parameters for new bonds
     *  @param _parameter PARAMETER
     *  @param _input uint256
     */
    function setBondTerms(
        PARAMETER _parameter,
        uint256 _input
    ) external onlyOwner {
        if (_parameter == PARAMETER.VESTING) {
            // 0
            require(_input >= 129600, "Vesting must be longer than 36 hours");
            terms.vestingTerm = _input;
        } else if (_parameter == PARAMETER.PAYOUT) {
            // 1
            require(_input <= 100000, "Cannot be greater than 100% of supply");
            terms.maxPayout = _input;
        } else if (_parameter == PARAMETER.DEBT) {
            // 2
            terms.maxDebt = _input;
        }
    }

    /**
     *  @notice set control variable adjustment
     *  @param _addition bool
     *  @param _increment uint256
     *  @param _target uint256
     *  @param _buffer uint256
     */
    function setAdjustment(
        bool _addition,
        uint256 _increment,
        uint256 _target,
        uint256 _buffer
    ) external onlyOwner {
        require(
            _increment <= terms.controlVariable.mul(30).div(1000),
            "Increment too large"
        );

        adjustment = Adjust({
            add: _addition,
            rate: _increment,
            target: _target,
            buffer: _buffer,
            lastBlockTimestamp: block.timestamp
        });
    }

    /// USER FUNCTIONS ///

    /**
     *  @notice deposit bond
     *  @param _amount uint256
     *  @param _maxPrice uint256
     *  @return uint256
     */
    function deposit(
        uint256 _amount,
        uint256 _maxPrice,
        MinAmountsLiq calldata _minAmounts
    ) external returns (uint256) {
        require(
            IERC20(principalToken).balanceOf(msg.sender) >= _amount,
            "Balance too low"
        );

        decayDebt();

        uint256 nativePrice = bondPrice();

        require(
            _maxPrice >= nativePrice,
            "Slippage limit: more than max price"
        ); // slippage protection

        uint256 value;
        uint256 payout;
        uint256 fee;

        (payout, fee, value) = payoutFor(_amount); // payout to bonder is computed

        if (!feeInVEC) _amount = _amount.sub(fee);

        require(payout >= 10 ** VEC.decimals() / 100, "Bond too small"); // must be > 0.01 payout token ( underflow protection )
        require(payout <= maxPayout(), "Bond too large"); // size protection because there is no slippage

        // total debt is increased
        totalDebt = totalDebt.add(value);

        require(totalDebt <= terms.maxDebt, "Max capacity reached");

        // depositor info is stored
        bondInfo[msg.sender] = Bond({
            payout: bondInfo[msg.sender].payout.add(payout),
            vesting: terms.vestingTerm,
            lastBlockTimestamp: block.timestamp,
            truePricePaid: bondPrice()
        });

        totalPrincipalBonded = totalPrincipalBonded.add(_amount); // total bonded increased
        totalPayoutGiven = totalPayoutGiven.add(payout); // total payout increased

        treasury.mint(address(this), payout);

        if (bondType == BondType.TAKEINPRINCIPAL) {
            principalToken.safeTransferFrom(
                msg.sender,
                address(treasury),
                _amount
            );
        } else if (bondType == BondType.WETHTOVETH) {
            principalToken.safeTransferFrom(msg.sender, address(this), _amount);
            IvETH(vETH).deposit(address(principalToken), address(treasury), _amount);
        } else {
            principalToken.safeTransferFrom(msg.sender, address(this), _amount);

            uint256 vecBefore = VEC.balanceOf(address(this));
            swapETHForTokens(_amount / 2, _minAmounts.minVECToSwap);
            addLiquidity(
                VEC.balanceOf(address(this)) - vecBefore,
                principalToken.balanceOf(address(this)),
                _minAmounts.minVECToAdd,
                _minAmounts.minWETHToAdd
            );
        }

        if (fee != 0) {
            if (feeInVEC) {
                treasury.mint(feeTo, fee);
            } else {
                principalToken.safeTransferFrom(msg.sender, feeTo, fee);
            }
        }

        // indexed events are emitted
        emit BondCreated(
            _amount,
            payout,
            block.timestamp.add(terms.vestingTerm)
        );
        emit BondPriceChanged(_bondPrice(), debtRatio());

        adjust(); // control variable is adjusted
        return payout;
    }

    /**
     *  @notice redeem bond for user
     *  @param _depositor address
     *  @return uint256
     */
    function redeem(address _depositor) external returns (uint256) {
        Bond memory info = bondInfo[_depositor];
        uint256 percentVested = percentVestedFor(_depositor); // (seconds since last interaction / vesting term remaining)

        if (percentVested >= 10000) {
            // if fully vested
            delete bondInfo[_depositor]; // delete user info
            emit BondRedeemed(_depositor, info.payout, 0); // emit bond data
            VEC.safeTransfer(_depositor, info.payout);
            return info.payout;
        } else {
            // if unfinished
            // calculate payout vested
            uint256 payout = info.payout.mul(percentVested).div(10000);

            // store updated deposit info
            bondInfo[_depositor] = Bond({
                payout: info.payout.sub(payout),
                vesting: info.vesting.sub(
                    block.timestamp.sub(info.lastBlockTimestamp)
                ),
                lastBlockTimestamp: block.timestamp,
                truePricePaid: info.truePricePaid
            });

            emit BondRedeemed(_depositor, payout, bondInfo[_depositor].payout);
            VEC.safeTransfer(_depositor, payout);
            return payout;
        }
    }

    /// INTERNAL HELPER FUNCTIONS ///

    /// @dev INTERNAL function to swap `ethAmount` for VEC
    function swapETHForTokens(uint256 ethAmount, uint256 minVEC) internal {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = uniswapV2Router.WETH();
        path[1] = address(VEC);

        // make the swap
        uniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            ethAmount,
            minVEC,
            path,
            address(this),
            block.timestamp
        );
    }

    /// @dev INTERNAL function to add `tokenAmount` and `ethAmount` to LP
    function addLiquidity(uint256 tokenAmount, uint256 ethAmount, uint256 minVEC, uint256 minWETH) internal {
        // add the liquidity
        uniswapV2Router.addLiquidity(
            address(VEC),
            address(principalToken),
            tokenAmount,
            ethAmount,
            minVEC,
            minWETH,
            address(treasury),
            block.timestamp
        );
    }

    /**
     *  @notice makes incremental adjustment to control variable
     */
    function adjust() internal {
        uint256 timestampCanAdjust = adjustment.lastBlockTimestamp.add(
            adjustment.buffer
        );
        if (adjustment.rate != 0 && block.timestamp >= timestampCanAdjust) {
            uint256 initial = terms.controlVariable;
            if (adjustment.add) {
                terms.controlVariable = terms.controlVariable.add(
                    adjustment.rate
                );
                if (terms.controlVariable >= adjustment.target) {
                    adjustment.rate = 0;
                }
            } else {
                terms.controlVariable = terms.controlVariable.sub(
                    adjustment.rate
                );
                if (terms.controlVariable <= adjustment.target) {
                    adjustment.rate = 0;
                }
            }
            adjustment.lastBlockTimestamp = block.timestamp;
            emit ControlVariableAdjustment(
                initial,
                terms.controlVariable,
                adjustment.rate,
                adjustment.add
            );
        }
    }

    /**
     *  @notice reduce total debt
     */
    function decayDebt() internal {
        totalDebt = totalDebt.sub(debtDecay());
        lastDecay = block.timestamp;
    }

    /**
     *  @notice calculate current bond price and remove floor if above
     *  @return price_ uint256
     */
    function _bondPrice() internal returns (uint256 price_) {
        price_ = terms.controlVariable.mul(debtRatio()).div(1e2);
        if (price_ < terms.minimumPrice) {
            price_ = terms.minimumPrice;
        } else if (terms.minimumPrice != 0) {
            terms.minimumPrice = 0;
        }
    }

    /// VIEW FUNCTIONS ///

    /**
     *  @notice calculate current bond premium
     *  @return price_ uint256
     */
    function bondPrice() public view returns (uint256 price_) {
        price_ = terms.controlVariable.mul(debtRatio()).div(1e2);
        if (price_ < terms.minimumPrice) {
            price_ = terms.minimumPrice;
        }
    }

    /**
     *  @notice determine maximum bond size
     *  @return uint256
     */
    function maxPayout() public view returns (uint256) {
        return VEC.totalSupply().mul(terms.maxPayout).div(100000);
    }

    /**
     *  @notice calculate user's interest due for new bond, accounting for Fee
     *  @param _amount uint256
     *  @return _payout uint256
     *  @return _fee uint256
     *  @return _value uint256
     */
    function payoutFor(
        uint256 _amount
    ) public view returns (uint256 _payout, uint256 _fee, uint256 _value) {
        if (!feeInVEC) {
            _fee = _amount.mul(feePercent).div(FEE_DENOM);
            _value = treasury.valueOfToken(
                address(principalToken),
                _amount.sub(_fee)
            );
            _payout = FixedPoint
                .fraction(_value, bondPrice())
                .decode112with18();
        } else {
            _value = treasury.valueOfToken(address(principalToken), _amount);
            uint256 total = FixedPoint
                .fraction(_value, bondPrice())
                .decode112with18();
            _payout = total;
            _fee = total.mul(feePercent).div(FEE_DENOM);
        }
    }

    /**
     *  @notice calculate current ratio of debt to payout token supply
     *  @return debtRatio_ uint256
     */
    function debtRatio() public view returns (uint256 debtRatio_) {
        debtRatio_ = FixedPoint
            .fraction(
                currentDebt().mul(10 ** VEC.decimals()),
                VEC.totalSupply()
            )
            .decode112with18()
            .div(1e9);
    }

    /**
     *  @notice calculate debt factoring in decay
     *  @return uint256
     */
    function currentDebt() public view returns (uint256) {
        return totalDebt.sub(debtDecay());
    }

    /**
     *  @notice amount to decay total debt by
     *  @return decay_ uint256
     */
    function debtDecay() public view returns (uint256 decay_) {
        uint256 timestampSinceLast = block.timestamp.sub(lastDecay);
        decay_ = totalDebt.mul(timestampSinceLast).div(terms.vestingTerm);
        if (decay_ > totalDebt) {
            decay_ = totalDebt;
        }
    }

    /**
     *  @notice calculate how far into vesting a depositor is
     *  @param _depositor address
     *  @return percentVested_ uint256
     */
    function percentVestedFor(
        address _depositor
    ) public view returns (uint256 percentVested_) {
        Bond memory bond = bondInfo[_depositor];
        uint256 timestampSinceLast = block.timestamp.sub(
            bond.lastBlockTimestamp
        );
        uint256 vesting = bond.vesting;

        if (vesting > 0) {
            percentVested_ = timestampSinceLast.mul(10000).div(vesting);
        } else {
            percentVested_ = 0;
        }
    }

    /**
     *  @notice calculate amount of payout token available for claim by depositor
     *  @param _depositor address
     *  @return pendingPayout_ uint256
     */
    function pendingPayoutFor(
        address _depositor
    ) external view returns (uint256 pendingPayout_) {
        uint256 percentVested = percentVestedFor(_depositor);
        uint256 payout = bondInfo[_depositor].payout;

        if (percentVested >= 10000) {
            pendingPayout_ = payout;
        } else {
            pendingPayout_ = payout.mul(percentVested).div(10000);
        }
    }
}
