pragma solidity ^0.8.0;

interface ICurveStableSwapNG {
    function exchange(int128 i, int128 j, uint256 _dx, uint256 _mint_dy) external;
}
