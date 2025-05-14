// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IStakingIDRX {
    // Struct definition based on the ABI
    struct Stake {
        uint256 stakeId;
        uint256 stakeType;
        address staker;
        bool isActive;
        bool isUnbonding;
        uint256 stakeAmount;
        uint256 rewardAmount;
        uint256 createdTimestamp;
        uint256 claimedAmount;
        uint256 claimedTimestamp;
        uint256 unlockTimestamp;
        uint256 unbondingTimestamp;
    }

    struct StakeType {
        uint256 rewardModifier;
        uint256 durationModifier;
        uint256 duration;
    }

    // Main functions from the ABI
    function newStake(uint256 amount, uint256 stakeType) external;
    function claimStakeReward(uint256 stakeId) external;
    function claimStakePrincipal(uint256 stakeId) external;
    function unbondStake(uint256 stakeId) external;
    function claimStakePrincipalUnbonded(uint256 stakeId) external;
    function getStake(uint256[] calldata stakeId) external view returns (Stake[] memory);
    function stakeTypes(uint256 typeId)
        external
        view
        returns (uint256 rewardModifier, uint256 durationModifier, uint256 duration);
    function stakeCount() external view returns (uint256);
    function stakeToken() external view returns (address);
}
