// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IUniswapV2Factory {
    event PairCreated(
        address indexed token0,
        address indexed token1,
        address pair,
        uint256
    );

    function feeTo() external view returns (address);

    function feeToSetter() external view returns (address);

    function getPair(
        address tokenA,
        address tokenB
    ) external view returns (address pair);

    function allPairs(uint256) external view returns (address pair);

    function allPairsLength() external view returns (uint256);

    function createPair(
        address tokenA,
        address tokenB
    ) external returns (address pair);

    function setFeeTo(address) external;

    function setFeeToSetter(address) external;
}

interface IUniswapV2Pair {
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
    event Transfer(address indexed from, address indexed to, uint256 value);

    function name() external pure returns (string memory);

    function symbol() external pure returns (string memory);

    function decimals() external pure returns (uint8);

    function totalSupply() external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    function approve(address spender, uint256 value) external returns (bool);

    function transfer(address to, uint256 value) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);

    function DOMAIN_SEPARATOR() external view returns (bytes32);

    function PERMIT_TYPEHASH() external pure returns (bytes32);

    function nonces(address owner) external view returns (uint256);

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(
        address indexed sender,
        uint256 amount0,
        uint256 amount1,
        address indexed to
    );
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    function MINIMUM_LIQUIDITY() external pure returns (uint256);

    function factory() external view returns (address);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function getReserves()
        external
        view
        returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    function price0CumulativeLast() external view returns (uint256);

    function price1CumulativeLast() external view returns (uint256);

    function kLast() external view returns (uint256);

    function mint(address to) external returns (uint256 liquidity);

    function burn(
        address to
    ) external returns (uint256 amount0, uint256 amount1);

    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external;

    function skim(address to) external;

    function sync() external;

    function initialize(address, address) external;
}

interface IUniswapV2Router02 {
    function factory() external pure returns (address);

    function WETH() external pure returns (address);

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

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        payable
        returns (uint256 amountToken, uint256 amountETH, uint256 liquidity);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

interface IWETH {
    function deposit() external payable;

    function withdraw(uint) external;
}

interface IvETH {
    function deposit(
        address _restakedLST,
        address _to,
        uint256 _amount
    ) external;
}

contract Vector is ERC20, Ownable {
    /// STATE VARIABLES ///

    /// @notice Address of UniswapV2Router
    IUniswapV2Router02 public immutable uniswapV2Router;
    /// @notice Address of VEC/ETH LP
    address public immutable uniswapV2Pair;
    /// @notice WETH address
    address public immutable WETH;
    /// @notice Address of vETH
    address public vETH;
    /// @notice VEC treasury
    address public treasury;
    /// @notice Team wallet address
    address public teamWallet;
    /// @notice vETH Reward Contract
    address public distributor;

    bool private swapping;

    /// @notice Bool if trading is active
    bool public tradingActive = false;
    /// @notice Bool if swap is enabled
    bool public swapEnabled = false;

    /// @notice Current percent of supply to swap tokens at (i.e. 50 = 0.05%)
    uint256 public swapPercent;

    /// @notice Current buy side total fees
    uint256 public buyTotalFees;
    /// @notice Current buy side backing fee
    uint256 public buyBackingFee;
    /// @notice Current buy side liquidity fee
    uint256 public buyLiquidityFee;
    /// @notice Current buy side team fee
    uint256 public buyTeamFee;
    /// @notice Current buy side vETH reward fee
    uint256 public buyvETHRewardFee;

    /// @notice Current sell side total fees
    uint256 public sellTotalFees;
    /// @notice Current sell side backing fee
    uint256 public sellBackingFee;
    /// @notice Current sell side liquidity fee
    uint256 public sellLiquidityFee;
    /// @notice Current sell side team fee
    uint256 public sellTeamFee;
    /// @notice Current sell side vETH reward fee
    uint256 public sellvETHRewardFee;

    /// @notice Current tokens going for backing
    uint256 public tokensForBacking;
    /// @notice Current tokens going for liquidity
    uint256 public tokensForLiquidity;
    /// @notice Current tokens going for team
    uint256 public tokensForTeam;
    /// @notice Current tokens going towards vETH reward fees
    uint256 public tokensForvETHRewards;

    /// MAPPINGS ///

    /// @dev Bool if address is excluded from fees
    mapping(address => bool) private _isExcludedFromFees;

    /// @notice Bool if address is AMM pair
    mapping(address => bool) public automatedMarketMakerPairs;

    /// EVENTS ///

    event ExcludeFromFees(address indexed account, bool isExcluded);

    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);

    event teamWalletUpdated(
        address indexed newWallet,
        address indexed oldWallet
    );

    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiquidity
    );

    event DistributorUpdated(address oldDistributor, address newDistributor);

    /// CONSTRUCTOR ///

    constructor() ERC20("Vector", "VEC") {
        WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(
            0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
        );

        uniswapV2Router = _uniswapV2Router;

        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());
        _setAutomatedMarketMakerPair(address(uniswapV2Pair), true);

        uint256 startingSupply_ = 10000000000000000;

        _approve(address(this), address(_uniswapV2Router), type(uint256).max);

        swapPercent = 100; // 0.10%

        buyBackingFee = 75;
        buyLiquidityFee = 75;
        buyTeamFee = 75;
        buyvETHRewardFee = 75;
        buyTotalFees = 300;

        sellBackingFee = 75;
        sellLiquidityFee = 75;
        sellTeamFee = 75;
        sellvETHRewardFee = 75;
        sellTotalFees = 300;

        teamWallet = owner(); // set as team wallet

        // exclude from paying fees or having max transaction amount
        excludeFromFees(owner(), true);
        excludeFromFees(address(this), true);

        _mint(msg.sender, startingSupply_);
    }

    receive() external payable {}

    /// AMM PAIR ///

    /// @notice       Sets if address is AMM pair
    /// @param pair   Address of pair
    /// @param value  Bool if AMM pair
    function setAutomatedMarketMakerPair(
        address pair,
        bool value
    ) public onlyOwner {
        require(
            pair != uniswapV2Pair,
            "The pair cannot be removed from automatedMarketMakerPairs"
        );

        _setAutomatedMarketMakerPair(pair, value);
    }

    /// @dev Internal function to set `vlaue` of `pair`
    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        automatedMarketMakerPairs[pair] = value;

        emit SetAutomatedMarketMakerPair(pair, value);
    }

    /// INTERNAL TRANSFER ///

    /// @dev Internal function to burn `amount` from `account`
    function _burnFrom(address account, uint256 amount) internal {
        uint256 decreasedAllowance_ = allowance(account, msg.sender) - amount;

        _approve(account, msg.sender, decreasedAllowance_);
        _burn(account, amount);
    }

    /// @dev Internal function to transfer - handles fee logic
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        if (amount == 0) {
            super._transfer(from, to, 0);
            return;
        }

        if (!tradingActive) {
            require(
                _isExcludedFromFees[from] || _isExcludedFromFees[to],
                "Trading is not active."
            );
        }

        uint256 contractTokenBalance = balanceOf(address(this));

        bool canSwap = contractTokenBalance >= swapTokensAtAmount();

        if (
            canSwap &&
            swapEnabled &&
            !swapping &&
            !automatedMarketMakerPairs[from] &&
            !_isExcludedFromFees[from] &&
            !_isExcludedFromFees[to]
        ) {
            swapping = true;

            swapBack();

            swapping = false;
        }

        bool takeFee = !swapping;

        // if any account belongs to _isExcludedFromFee account then remove the fee
        if (_isExcludedFromFees[from] || _isExcludedFromFees[to]) {
            takeFee = false;
        }

        uint256 fees;
        // only take fees on buys/sells, do not take on wallet transfers
        if (takeFee) {
            // on sell
            if (automatedMarketMakerPairs[to] && sellTotalFees > 0) {
                fees = (amount * sellTotalFees) / 10000;
                tokensForLiquidity += (fees * sellLiquidityFee) / sellTotalFees;
                tokensForTeam += (fees * sellTeamFee) / sellTotalFees;
                tokensForBacking += (fees * sellBackingFee) / sellTotalFees;
                tokensForvETHRewards +=
                    (fees * sellvETHRewardFee) /
                    sellTotalFees;
            }
            // on buy
            else if (automatedMarketMakerPairs[from] && buyTotalFees > 0) {
                fees = (amount * buyTotalFees) / 10000;
                tokensForLiquidity += (fees * buyLiquidityFee) / buyTotalFees;
                tokensForTeam += (fees * buyTeamFee) / buyTotalFees;
                tokensForBacking += (fees * buyBackingFee) / buyTotalFees;
                tokensForvETHRewards +=
                    (fees * buyvETHRewardFee) /
                    buyTotalFees;
            }

            if (fees > 0) {
                super._transfer(from, address(this), fees);
            }

            amount -= fees;
        }

        super._transfer(from, to, amount);
    }

    /// INTERNAL FUNCTION ///

    /// @dev INTERNAL function to swap `tokenAmount` for ETH
    /// @dev Invoked in `swapBack()`
    function swapTokensForEth(uint256 tokenAmount) internal {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    /// @dev INTERNAL function to add `tokenAmount` and `ethAmount` to LP
    /// @dev Invoked in `swapBack()`
    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) internal {
        // add the liquidity
        uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            treasury,
            block.timestamp
        );
    }

    /// @dev INTERNAL function to transfer fees properly
    /// @dev Invoked in `_transfer()`
    function swapBack() internal {
        uint256 contractBalance = balanceOf(address(this));
        uint256 totalTokensToSwap = tokensForLiquidity +
            tokensForBacking +
            tokensForTeam +
            tokensForvETHRewards;

        bool success;

        if (contractBalance == 0 || totalTokensToSwap == 0) {
            return;
        }

        if (contractBalance > swapTokensAtAmount() * 20) {
            contractBalance = swapTokensAtAmount() * 20;
        }

        // Halve the amount of liquidity tokens
        uint256 liquidityTokens = (contractBalance * tokensForLiquidity) /
            totalTokensToSwap /
            2;

        uint256 amountToSwapForETH = contractBalance - liquidityTokens;

        if (amountToSwapForETH > 0) swapTokensForEth(amountToSwapForETH);

        uint256 ethBalance = address(this).balance;

        uint256 ethForBacking = (ethBalance * tokensForBacking) /
            (totalTokensToSwap - tokensForLiquidity / 2);

        uint256 ethForTeam = (ethBalance * tokensForTeam) /
            (totalTokensToSwap - tokensForLiquidity / 2);

        uint256 ethForvETHReward = (ethBalance * tokensForvETHRewards) /
            (totalTokensToSwap - tokensForLiquidity / 2);

        uint256 ethForLiquidity = ethBalance -
            ethForBacking -
            ethForTeam -
            ethForvETHReward;

        tokensForLiquidity = 0;
        tokensForBacking = 0;
        tokensForTeam = 0;
        tokensForvETHRewards = 0;

        (success, ) = address(teamWallet).call{value: ethForTeam}("");
        (success, ) = address(distributor).call{value: ethForvETHReward}("");

        if (liquidityTokens > 0 && ethForLiquidity > 0) {
            addLiquidity(liquidityTokens, ethForLiquidity);
            emit SwapAndLiquify(
                amountToSwapForETH,
                ethForLiquidity,
                liquidityTokens
            );
        }

        uint256 _balance = address(this).balance;
        if (_balance > 0) {
            IWETH(WETH).deposit{value: _balance}();
            IvETH(vETH).deposit(WETH, treasury, _balance);
        }
    }

    /// VIEW FUNCTION ///

    /// @notice Returns decimals for VEC (9)
    function decimals() public view virtual override returns (uint8) {
        return 9;
    }

    /// @notice Returns if address is excluded from fees
    function isExcludedFromFees(address account) public view returns (bool) {
        return _isExcludedFromFees[account];
    }

    /// @notice Returns at what percent of supply to swap tokens at
    function swapTokensAtAmount() public view returns (uint256 amount_) {
        amount_ = (totalSupply() * swapPercent) / 100000;
    }

    /// USER FUNCTIONS ///

    /// @notice         Burn VEC
    /// @param account  Address to burn VEC from
    /// @param amount   Amount to VEC to burn
    function burnFrom(address account, uint256 amount) external {
        _burnFrom(account, amount);
    }

    /// @notice         Burn VEC
    /// @param amount   Amount to VEC to burn
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    /// OWNER FUNCTIONS ///

    function mint(address account_, uint256 amount_) external {
        require(msg.sender == treasury, "Not Treasury");
        _mint(account_, amount_);
    }

    /// @notice Initialize
    function initialize(
        address _treasury,
        address _distributor,
        address _vETH
    ) external onlyOwner {
        require(treasury == address(0), "Treasury already set");
        treasury = _treasury;
        excludeFromFees(_treasury, true);
        distributor = _distributor;
        vETH = _vETH;
        IERC20(WETH).approve(vETH, type(uint256).max);
    }

    /// @notice Update distributor
    function updateDistributor(address _distributor) external onlyOwner {
        address oldDistributor = distributor;
        distributor = _distributor;
        emit DistributorUpdated(oldDistributor, _distributor);
    }

    /// @notice Enable trading - once enabled, can never be turned off
    function enableTrading() external onlyOwner {
        require(!tradingActive, "Already Enabled");
        tradingActive = true;
        swapEnabled = true;
    }

    /// @notice Update percent of supply to swap tokens at
    function updateSwapTokensAtPercent(
        uint256 newPercent
    ) external onlyOwner returns (bool) {
        require(
            newPercent >= 1,
            "Swap amount cannot be lower than 0.001% total supply."
        );
        require(
            newPercent <= 500,
            "Swap amount cannot be higher than 0.50% total supply."
        );
        swapPercent = newPercent;
        return true;
    }

    /// @notice Update swap enabled
    /// @dev    Only use to disable contract sales if absolutely necessary (emergency use only)
    function updateSwapEnabled(bool enabled) external onlyOwner {
        swapEnabled = enabled;
    }

    /// @notice Update buy side fees
    function updateBuyFees(
        uint256 _backingFee,
        uint256 _liquidityFee,
        uint256 _teamFee,
        uint256 _vETHRewardFee
    ) external onlyOwner {
        buyBackingFee = _backingFee;
        buyLiquidityFee = _liquidityFee;
        buyTeamFee = _teamFee;
        buyvETHRewardFee = _vETHRewardFee;
        buyTotalFees =
            buyBackingFee +
            buyLiquidityFee +
            buyTeamFee +
            buyvETHRewardFee;
        require(buyTotalFees <= 300, "Buy fees must be <= 3%");
    }

    /// @notice Update sell side fees
    function updateSellFees(
        uint256 _backingFee,
        uint256 _liquidityFee,
        uint256 _teamFee,
        uint256 _vETHRewardFee
    ) external onlyOwner {
        sellBackingFee = _backingFee;
        sellLiquidityFee = _liquidityFee;
        sellTeamFee = _teamFee;
        sellvETHRewardFee = _vETHRewardFee;
        sellTotalFees =
            sellBackingFee +
            sellLiquidityFee +
            sellTeamFee +
            sellvETHRewardFee;
        require(sellTotalFees <= 300, "Sell fees must be <= 3%");
    }

    /// @notice Set if an address is excluded from fees
    function excludeFromFees(address account, bool excluded) public onlyOwner {
        _isExcludedFromFees[account] = excluded;
        emit ExcludeFromFees(account, excluded);
    }

    /// @notice Update team wallet
    function updateTeamWallet(address newWallet) external onlyOwner {
        emit teamWalletUpdated(newWallet, teamWallet);
        teamWallet = newWallet;
        excludeFromFees(newWallet, true);
    }

    /// @notice Withdraw stuck token from contract
    function withdrawStuckToken(
        address _token,
        address _to
    ) external onlyOwner {
        require(_token != address(0), "_token address cannot be 0");
        uint256 _contractBalance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).transfer(_to, _contractBalance);
    }

    /// @notice Withdraw stuck ETH from contract
    function withdrawStuckEth(address toAddr) external onlyOwner {
        (bool success, ) = toAddr.call{value: address(this).balance}("");
        require(success);
    }
}
