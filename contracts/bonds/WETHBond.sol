// import "../libraries/SafeMath.sol";
// import "../libraries/FixedPoint.sol";
// import "../libraries/Address.sol";
// import "../libraries/SafeERC20.sol";
// import "../interface/ITreasury.sol";

// // SPDX-License-Identifier: AGPL-3.0-or-later
// pragma solidity ^0.7.5;

// interface IvETH {
//     function deposit(
//         address _restakedLST,
//         address _to,
//         uint256 _amount
//     ) external;
// }

// contract VectorWETHBonding {
//     using FixedPoint for *;
//     using SafeERC20 for IERC20;
//     using SafeMath for uint256;

//     modifier onlyOwner() {
//         require(owner == msg.sender, "Ownable: caller is not the owner");
//         _;
//     }

//     /// EVENTS ///

//     event BondCreated(uint256 deposit, uint256 payout, uint256 expires);
//     event BondRedeemed(address recipient, uint256 payout, uint256 remaining);
//     event BondPriceChanged(uint256 internalPrice, uint256 debtRatio);
//     event ControlVariableAdjustment(
//         uint256 initialBCV,
//         uint256 newBCV,
//         uint256 adjustment,
//         bool addition
//     );

//     /// STATE VARIABLES ///

//     uint256 public constant FEE_DENOM = 1_000_000;

//     address public owner;

//     IERC20 public immutable VEC; // token paid for principal
//     IERC20 public immutable WETH; // inflow token
//     ITreasury public immutable treasury; // pays for and receives principal

//     address public feeTo;
//     address public immutable vETH;
//     // in ten-thousandths of a %. i.e. 5000 = 0.5%
//     uint256 public feePercent;

//     uint256 public totalPrincipalBonded;
//     uint256 public totalPayoutGiven;
//     uint256 public totalDebt; // total value of outstanding bonds; used for pricing
//     uint256 public lastDecay; // reference timestamp for debt decay

//     Terms public terms; // stores terms for new bonds
//     Adjust public adjustment; // stores adjustment to BCV data

//     bool public immutable feeInVEC;

//     mapping(address => Bond) public bondInfo; // stores bond information for depositors

//     /// STRUCTS ///

//     // Info for creating new bonds
//     struct Terms {
//         uint256 controlVariable; // scaling variable for price
//         uint256 vestingTerm; // in seconds
//         uint256 minimumPrice; // vs principal value
//         uint256 maxPayout; // in thousandths of a %. i.e. 500 = 0.5%
//         uint256 maxDebt; // payout token decimal debt ratio, max % total supply created as debt
//     }

//     // Info for bond holder
//     struct Bond {
//         uint256 payout; // payout token remaining to be paid
//         uint256 vesting; // seconds left to vest
//         uint256 lastBlockTimestamp; // Last interaction
//         uint256 truePricePaid; // Price paid (principal tokens per payout token) in ten-millionths - 4000000 = 0.4
//     }

//     // Info for incremental adjustments to control variable
//     struct Adjust {
//         bool add; // addition or subtraction
//         uint256 rate; // increment
//         uint256 target; // BCV when adjustment finished
//         uint256 buffer; // minimum length (in seconds) between adjustments
//         uint256 lastBlockTimestamp; // timestamp when last adjustment made
//     }

//     /// CONSTRUCTOR ///

//     constructor(
//         address _treasury,
//         address _vETH,
//         address _WETH,
//         bool _feeInVEC
//     ) {
//         treasury = ITreasury(_treasury);
//         VEC = IERC20(ITreasury(_treasury).VEC());
//         WETH = IERC20(_WETH);
//         owner = msg.sender;
//         vETH = _vETH;
//         feeInVEC = _feeInVEC;
//     }

//     /// INITIALIZATION ///

//     /**
//      *  @notice initializes bond parameters
//      *  @param _controlVariable uint256
//      *  @param _vestingTerm uint256
//      *  @param _minimumPrice uint256
//      *  @param _maxPayout uint256
//      *  @param _maxDebt uint256
//      *  @param _initialDebt uint256
//      */
//     function initializeBond(
//         uint256 _controlVariable,
//         uint256 _vestingTerm,
//         uint256 _minimumPrice,
//         uint256 _maxPayout,
//         uint256 _maxDebt,
//         uint256 _initialDebt
//     ) external onlyOwner {
//         require(currentDebt() == 0, "Debt must be 0 for initialization");
//         WETH.approve(vETH, type(uint256).max);
//         terms = Terms({
//             controlVariable: _controlVariable,
//             vestingTerm: _vestingTerm,
//             minimumPrice: _minimumPrice,
//             maxPayout: _maxPayout,
//             maxDebt: _maxDebt
//         });
//         totalDebt = _initialDebt;
//         lastDecay = block.timestamp;
//     }

//     /// POLICY FUNCTIONS ///

//     function setFeeAndFeeTo(
//         address feeTo_,
//         uint256 feePercent_
//     ) external onlyOwner {
//         feeTo = feeTo_;
//         feePercent = feePercent_;
//     }

//     function transferOwnership(address newOwner) external virtual onlyOwner {
//         require(
//             newOwner != address(0),
//             "Ownable: new owner is the zero address"
//         );
//         owner = newOwner;
//     }

//     enum PARAMETER {
//         VESTING,
//         PAYOUT,
//         DEBT
//     }

//     /**
//      *  @notice set parameters for new bonds
//      *  @param _parameter PARAMETER
//      *  @param _input uint256
//      */
//     function setBondTerms(
//         PARAMETER _parameter,
//         uint256 _input
//     ) external onlyOwner {
//         if (_parameter == PARAMETER.VESTING) {
//             // 0
//             require(_input >= 129600, "Vesting must be longer than 36 hours");
//             terms.vestingTerm = _input;
//         } else if (_parameter == PARAMETER.PAYOUT) {
//             // 1
//             terms.maxPayout = _input;
//         } else if (_parameter == PARAMETER.DEBT) {
//             // 2
//             terms.maxDebt = _input;
//         }
//     }

//     /**
//      *  @notice set control variable adjustment
//      *  @param _addition bool
//      *  @param _increment uint256
//      *  @param _target uint256
//      *  @param _buffer uint256
//      */
//     function setAdjustment(
//         bool _addition,
//         uint256 _increment,
//         uint256 _target,
//         uint256 _buffer
//     ) external onlyOwner {
//         require(
//             _increment <= terms.controlVariable.mul(30).div(1000),
//             "Increment too large"
//         );

//         adjustment = Adjust({
//             add: _addition,
//             rate: _increment,
//             target: _target,
//             buffer: _buffer,
//             lastBlockTimestamp: block.timestamp
//         });
//     }

//     /// USER FUNCTIONS ///

//     /**
//      *  @notice deposit bond
//      *  @param _amount uint256
//      *  @param _maxPrice uint256
//      *  @param _depositor address
//      *  @return uint256
//      */
//     function deposit(
//         uint256 _amount,
//         uint256 _maxPrice,
//         address _depositor
//     ) external returns (uint256) {
//         require(_depositor != address(0), "Invalid address");
//         require(WETH.balanceOf(msg.sender) >= _amount, "Balance too low");

//         decayDebt();

//         uint256 nativePrice = bondPrice();

//         require(
//             _maxPrice >= nativePrice,
//             "Slippage limit: more than max price"
//         ); // slippage protection

//         uint256 value;
//         uint256 payout;
//         uint256 fee;

//         (payout, fee, value) = payoutFor(_amount); // payout to bonder is computed

//         if (!feeInVEC) _amount = _amount.sub(fee);

//         require(payout >= 10 ** VEC.decimals() / 100, "Bond too small"); // must be > 0.01 payout token ( underflow protection )
//         require(payout <= maxPayout(), "Bond too large"); // size protection because there is no slippage

//         // total debt is increased
//         totalDebt = totalDebt.add(value);

//         require(totalDebt <= terms.maxDebt, "Max capacity reached");

//         // depositor info is stored
//         bondInfo[_depositor] = Bond({
//             payout: bondInfo[_depositor].payout.add(payout),
//             vesting: terms.vestingTerm,
//             lastBlockTimestamp: block.timestamp,
//             truePricePaid: bondPrice()
//         });

//         totalPrincipalBonded = totalPrincipalBonded.add(_amount); // total bonded increased
//         totalPayoutGiven = totalPayoutGiven.add(payout); // total payout increased

//         treasury.mint(address(this), payout);
//         WETH.safeTransferFrom(msg.sender, address(this), _amount);
//         IvETH(vETH).deposit(address(WETH), address(treasury), _amount);

//         if (fee != 0) {
//             if (feeInVEC) {
//                 treasury.mint(feeTo, fee);
//             } else {
//                 WETH.safeTransferFrom(msg.sender, feeTo, fee);
//             }
//         }

//         // indexed events are emitted
//         emit BondCreated(
//             _amount,
//             payout,
//             block.timestamp.add(terms.vestingTerm)
//         );
//         emit BondPriceChanged(_bondPrice(), debtRatio());

//         adjust(); // control variable is adjusted
//         return payout;
//     }

//     /**
//      *  @notice redeem bond for user
//      *  @param _depositor address
//      *  @return uint256
//      */
//     function redeem(address _depositor) external returns (uint256) {
//         Bond memory info = bondInfo[_depositor];
//         uint256 percentVested = percentVestedFor(_depositor); // (seconds since last interaction / vesting term remaining)

//         if (percentVested >= 10000) {
//             // if fully vested
//             delete bondInfo[_depositor]; // delete user info
//             emit BondRedeemed(_depositor, info.payout, 0); // emit bond data
//             VEC.safeTransfer(_depositor, info.payout);
//             return info.payout;
//         } else {
//             // if unfinished
//             // calculate payout vested
//             uint256 payout = info.payout.mul(percentVested).div(10000);

//             // store updated deposit info
//             bondInfo[_depositor] = Bond({
//                 payout: info.payout.sub(payout),
//                 vesting: info.vesting.sub(
//                     block.timestamp.sub(info.lastBlockTimestamp)
//                 ),
//                 lastBlockTimestamp: block.timestamp,
//                 truePricePaid: info.truePricePaid
//             });

//             emit BondRedeemed(_depositor, payout, bondInfo[_depositor].payout);
//             VEC.safeTransfer(_depositor, payout);
//             return payout;
//         }
//     }

//     /// INTERNAL HELPER FUNCTIONS ///

//     /**
//      *  @notice makes incremental adjustment to control variable
//      */
//     function adjust() internal {
//         uint256 timestampCanAdjust = adjustment.lastBlockTimestamp.add(
//             adjustment.buffer
//         );
//         if (adjustment.rate != 0 && block.timestamp >= timestampCanAdjust) {
//             uint256 initial = terms.controlVariable;
//             if (adjustment.add) {
//                 terms.controlVariable = terms.controlVariable.add(
//                     adjustment.rate
//                 );
//                 if (terms.controlVariable >= adjustment.target) {
//                     adjustment.rate = 0;
//                 }
//             } else {
//                 terms.controlVariable = terms.controlVariable.sub(
//                     adjustment.rate
//                 );
//                 if (terms.controlVariable <= adjustment.target) {
//                     adjustment.rate = 0;
//                 }
//             }
//             adjustment.lastBlockTimestamp = block.timestamp;
//             emit ControlVariableAdjustment(
//                 initial,
//                 terms.controlVariable,
//                 adjustment.rate,
//                 adjustment.add
//             );
//         }
//     }

//     /**
//      *  @notice reduce total debt
//      */
//     function decayDebt() internal {
//         totalDebt = totalDebt.sub(debtDecay());
//         lastDecay = block.timestamp;
//     }

//     /**
//      *  @notice calculate current bond price and remove floor if above
//      *  @return price_ uint256
//      */
//     function _bondPrice() internal returns (uint256 price_) {
//         price_ = terms.controlVariable.mul(debtRatio()).div(1e2);
//         if (price_ < terms.minimumPrice) {
//             price_ = terms.minimumPrice;
//         } else if (terms.minimumPrice != 0) {
//             terms.minimumPrice = 0;
//         }
//     }

//     /// VIEW FUNCTIONS ///

//     /**
//      *  @notice calculate current bond premium
//      *  @return price_ uint256
//      */
//     function bondPrice() public view returns (uint256 price_) {
//         price_ = terms.controlVariable.mul(debtRatio()).div(1e2);
//         if (price_ < terms.minimumPrice) {
//             price_ = terms.minimumPrice;
//         }
//     }

//     /**
//      *  @notice determine maximum bond size
//      *  @return uint256
//      */
//     function maxPayout() public view returns (uint256) {
//         return VEC.totalSupply().mul(terms.maxPayout).div(100000);
//     }

//     /**
//      *  @notice calculate user's interest due for new bond, accounting for Fee
//      *  @param _amount uint256
//      *  @return _payout uint256
//      *  @return _fee uint256
//      *  @return _value uint256
//      */
//     function payoutFor(
//         uint256 _amount
//     ) public view returns (uint256 _payout, uint256 _fee, uint256 _value) {
//         if (!feeInVEC) {
//             _fee = _amount.mul(feePercent).div(FEE_DENOM);
//             _value = treasury.valueOfToken(address(WETH), _amount.sub(_fee));
//             _payout = FixedPoint
//                 .fraction(_value, bondPrice())
//                 .decode112with18();
//         } else {
//             _value = treasury.valueOfToken(address(WETH), _amount);
//             uint256 total = FixedPoint
//                 .fraction(_value, bondPrice())
//                 .decode112with18();
//             _payout = total;
//             _fee = total.mul(feePercent).div(FEE_DENOM);
//         }
//     }

//     /**
//      *  @notice calculate current ratio of debt to payout token supply
//      *  @return debtRatio_ uint256
//      */
//     function debtRatio() public view returns (uint256 debtRatio_) {
//         debtRatio_ = FixedPoint
//             .fraction(
//                 currentDebt().mul(10 ** VEC.decimals()),
//                 VEC.totalSupply()
//             )
//             .decode112with18()
//             .div(1e9);
//     }

//     /**
//      *  @notice calculate debt factoring in decay
//      *  @return uint256
//      */
//     function currentDebt() public view returns (uint256) {
//         return totalDebt.sub(debtDecay());
//     }

//     /**
//      *  @notice amount to decay total debt by
//      *  @return decay_ uint256
//      */
//     function debtDecay() public view returns (uint256 decay_) {
//         uint256 timestampSinceLast = block.timestamp.sub(lastDecay);
//         decay_ = totalDebt.mul(timestampSinceLast).div(terms.vestingTerm);
//         if (decay_ > totalDebt) {
//             decay_ = totalDebt;
//         }
//     }

//     /**
//      *  @notice calculate how far into vesting a depositor is
//      *  @param _depositor address
//      *  @return percentVested_ uint256
//      */
//     function percentVestedFor(
//         address _depositor
//     ) public view returns (uint256 percentVested_) {
//         Bond memory bond = bondInfo[_depositor];
//         uint256 timestampSinceLast = block.timestamp.sub(
//             bond.lastBlockTimestamp
//         );
//         uint256 vesting = bond.vesting;

//         if (vesting > 0) {
//             percentVested_ = timestampSinceLast.mul(10000).div(vesting);
//         } else {
//             percentVested_ = 0;
//         }
//     }

//     /**
//      *  @notice calculate amount of payout token available for claim by depositor
//      *  @param _depositor address
//      *  @return pendingPayout_ uint256
//      */
//     function pendingPayoutFor(
//         address _depositor
//     ) external view returns (uint256 pendingPayout_) {
//         uint256 percentVested = percentVestedFor(_depositor);
//         uint256 payout = bondInfo[_depositor].payout;

//         if (percentVested >= 10000) {
//             pendingPayout_ = payout;
//         } else {
//             pendingPayout_ = payout.mul(percentVested).div(10000);
//         }
//     }
// }
