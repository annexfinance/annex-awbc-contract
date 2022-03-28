// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./interfaces/IBoostToken.sol";
import "./interfaces/IERC721Receiver.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IVANN.sol";
import "./libraries/SafeERC20.sol";
import "./libraries/EnumerableSet.sol";
import "./libraries/SafeMath.sol";
import "./libraries/Ownable.sol";
import "./libraries/ReentrancyGuard.sol";
import "hardhat/console.sol";

// AnnexFarm is the master of Farm.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once ANN is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract AnnexBoostFarm is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 pendingAmount; // non-eligible lp amount for reward
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 depositedDate; // Latest deposited date
        //
        // We do some fancy math here. Basically, any point in time, the amount of ANNs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accRewardPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accRewardPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
        uint256[] boostFactors;
        uint256 boostRewardDebt; // Boost Reward debt. See explanation below.
        uint256 boostedDate; // Latest boosted date
        uint256 accBoostReward;
    }
    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. ANNs to distribute per block.
        uint256 lastRewardBlock; // Last block number that ANNs distribution occurs.
        uint256 accRewardPerShare; // Accumulated ANNs per share, times 1e12. See below.
        uint256 totalBoostCount; // Total valid boosted accounts count.
        uint256 rewardEligibleSupply; // total LP supply of users which staked boost token.
    }
    // The Annex TOKEN!
    address public annex;
    // The vAnnex TOKEN!
    address public vAnn;
    // The Reward TOKEN!
    address public rewardToken;
    // Block number when bonus ANN period ends.
    uint256 public bonusEndBlock;
    // ANN tokens created per block.
    uint256 public rewardPerBlock;
    // Bonus muliplier for early annex makers.
    uint256 public constant BONUS_MULTIPLIER = 10;
    // VANN minting rate
    uint256 public constant VANN_RATE = 10;
    // Info of each pool.
    PoolInfo[] private poolInfo;
    // Total ANN amount deposited in ANN single pool. To reduce tx-fee, not included in struct PoolInfo.
    uint256 private lpSupplyOfAnnPool;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // claimable time limit for base reward
    uint256 public claimBaseRewardTime = 86400;
    uint256 public unstakableTime = 172800;
    uint256 public initialBoostMultiplier = 40;
    uint256 public boostMultiplierFactor = 20;

    // Boosting Part
    // Minimum vaild boost NFT count
    uint16 public minimumValidBoostCount = 1;
    // Maximum boost NFT count
    uint16 public maximumBoostCount = 10;
    // NFT contract for boosting
    IBoostToken public boostFactor;
    // Boosted with NFT or not
    mapping (uint256 => bool) public isBoosted;
    // claimable time limit for boost reward
    uint256 public claimBoostRewardTime = 86400 * 30;
    // boosted user list
    mapping(uint256 => address[]) private boostedUsers;

    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when ANN mining starts.
    uint256 public startBlock;
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );
    event Boost(address indexed user, uint256 indexed pid, uint256 tokenId);
    event UnBoost(address indexed user, uint256 indexed pid, uint256 tokenId);

    constructor(
        address _annex,
        address _rewardToken,
        address _vAnn,
        address _boost,
        uint256 _rewardPerBlock,
        uint256 _startBlock,
        uint256 _bonusEndBlock
    ) public {
        annex = _annex;
        rewardToken = _rewardToken;
        vAnn = _vAnn;
        boostFactor = IBoostToken(_boost);
        rewardPerBlock = _rewardPerBlock;
        bonusEndBlock = _bonusEndBlock;
        startBlock = _startBlock;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function getPoolInfo(uint _pid) external view returns (
        IERC20 lpToken,
        uint256 lpSupply,
        uint256 allocPoint,
        uint256 lastRewardBlock,
        uint accRewardPerShare,
        uint totalBoostCount,
        uint256 rewardEligibleSupply
    ) {
        PoolInfo storage pool = poolInfo[_pid];
        uint256 amount;
        if (annex == address(pool.lpToken)) {
            amount = lpSupplyOfAnnPool;
        } else {
            amount = pool.lpToken.balanceOf(address(this));
        }
        return (
            pool.lpToken,
            amount,
            pool.allocPoint,
            pool.lastRewardBlock,
            pool.accRewardPerShare,
            pool.totalBoostCount,
            pool.rewardEligibleSupply
        );
    }

    function getUserInfo(uint _pid, address _user) external view returns (
        uint256 amount,
        uint256 pendingAmount,
        uint256 rewardDebt,
        uint256 depositedDate,
        uint256 boostRewardDebt,
        uint256 boostedDate,
        uint256 accBoostReward
    ) {
        UserInfo storage user = userInfo[_pid][_user];

        return (
            user.amount,
            user.pendingAmount,
            user.rewardDebt,
            user.depositedDate,
            user.boostRewardDebt,
            user.boostedDate,
            user.accBoostReward
        );
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(
        uint256 _allocPoint,
        IERC20 _lpToken,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock =
            block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accRewardPerShare: 0,
                totalBoostCount: 0,
                rewardEligibleSupply: 0
            })
        );
    }

    // Update the given pool's ANN allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // Update the given ANN per block. Can only be called by the owner.
    function setRewardPerBlock(
        uint256 speed
    ) public onlyOwner {
        rewardPerBlock = speed;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to)
        public
        view
        returns (uint256)
    {
        if (_to <= bonusEndBlock) {
            return _to.sub(_from).mul(BONUS_MULTIPLIER);
        } else if (_from >= bonusEndBlock) {
            return _to.sub(_from);
        } else {
            return
                bonusEndBlock.sub(_from).mul(BONUS_MULTIPLIER).add(
                    _to.sub(bonusEndBlock)
                );
        }
    }

    function getValidBoostFactors(uint256 userBoostFactors) internal view returns (uint256) {
        uint256 validBoostFactors = userBoostFactors > minimumValidBoostCount ? userBoostFactors - minimumValidBoostCount : 0;

        return validBoostFactors;
    }

    function getBoostMultiplier(uint256 boostFactorCount) internal view returns (uint256) {
        if (boostFactorCount <= minimumValidBoostCount) {
            return 0;
        }
        uint256 initBoostCount = boostFactorCount.sub(minimumValidBoostCount + 1);

        return initBoostCount.mul(boostMultiplierFactor).add(initialBoostMultiplier);
    }

    // View function to see pending ANNs on frontend.
    function pendingReward(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accRewardPerShare = pool.accRewardPerShare;

        if (block.number > pool.lastRewardBlock && pool.rewardEligibleSupply > 0) {
            uint256 multiplier =
                getMultiplier(pool.lastRewardBlock, block.number);
            uint256 reward =
                multiplier.mul(rewardPerBlock).mul(pool.allocPoint).div(
                    totalAllocPoint
                );
            accRewardPerShare = accRewardPerShare.add(
                reward.mul(1e12).div(pool.rewardEligibleSupply)
            );
        }
        uint256 boostMultiplier = getBoostMultiplier(user.boostFactors.length);
        uint256 baseReward = user.amount.mul(accRewardPerShare).div(1e12).sub(user.rewardDebt);
        uint256 boostReward = boostMultiplier.mul(baseReward).add(user.accBoostReward).sub(user.boostRewardDebt).div(100);
        return baseReward.add(boostReward);
    }

    // View function to see pending ANNs on frontend.
    function pendingBaseReward(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accRewardPerShare = pool.accRewardPerShare;

        if (block.number > pool.lastRewardBlock && pool.rewardEligibleSupply > 0) {
            uint256 multiplier =
                getMultiplier(pool.lastRewardBlock, block.number);
            uint256 reward =
                multiplier.mul(rewardPerBlock).mul(pool.allocPoint).div(
                    totalAllocPoint
                );
            accRewardPerShare = accRewardPerShare.add(
                reward.mul(1e12).div(pool.rewardEligibleSupply)
            );
        }

        return user.amount.mul(accRewardPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward vairables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }

        if (pool.rewardEligibleSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 reward =
            multiplier.mul(rewardPerBlock).mul(pool.allocPoint).div(
                totalAllocPoint
            );
        pool.accRewardPerShare = pool.accRewardPerShare.add(
            reward.mul(1e12).div(pool.rewardEligibleSupply)
        );
        pool.lastRewardBlock = block.number;
    }

    // Check the eligible user or not for reward
    function checkRewardEligible(uint boost) internal view returns(bool) {
        if (boost >= minimumValidBoostCount) {
            return true;
        }

        return false;
    }

    // Check claim eligible
    function checkRewardClaimEligible(uint depositedTime) internal view returns(bool) {
        if (block.timestamp - depositedTime > claimBaseRewardTime) {
            return true;
        }

        return false;
    }

    // Claim base lp reward
    function _claimBaseRewards(uint256 _pid, address _user) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        bool claimEligible = checkRewardClaimEligible(user.depositedDate);
        if (claimEligible) {
            uint256 accRewardPerShare = pool.accRewardPerShare;

            if (pool.rewardEligibleSupply > 0) {
                uint256 multiplier =
                    getMultiplier(pool.lastRewardBlock, block.number);
                uint256 reward =
                    multiplier.mul(rewardPerBlock).mul(pool.allocPoint).div(
                        totalAllocPoint
                    );
                accRewardPerShare = accRewardPerShare.add(
                    reward.mul(1e12).div(pool.rewardEligibleSupply)
                );
            }
            uint256 boostMultiplier = getBoostMultiplier(user.boostFactors.length);
            uint256 baseReward = user.amount.mul(accRewardPerShare).div(1e12).sub(user.rewardDebt);
            uint256 boostReward = boostMultiplier.mul(baseReward);
            user.accBoostReward = user.accBoostReward.add(boostReward);

            if (baseReward > 0) {
                safeRewardTransfer(_user, baseReward);
            }
            pool.lastRewardBlock = block.number;
            user.rewardDebt = user.amount.mul(pool.accRewardPerShare).div(1e12);
            user.depositedDate = block.timestamp;
        }
    }

    function claimBaseRewards(uint256 _pid) external {
        // updatePool(_pid);
        _claimBaseRewards(_pid, msg.sender);
    }

    // Deposit LP tokens to Annexswap for ANN allocation.
    function deposit(uint256 _pid, uint256 _amount) external {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        // updatePool(_pid);
        bool claimEligible = checkRewardClaimEligible(user.depositedDate);
        bool rewardEligible = checkRewardEligible(user.boostFactors.length);

        if (claimEligible && rewardEligible) {
            _claimBaseRewards(_pid, msg.sender);
        }

        pool.lpToken.safeTransferFrom(
            address(msg.sender),
            address(this),
            _amount
        );
        if (annex == address(pool.lpToken)) {
            lpSupplyOfAnnPool = lpSupplyOfAnnPool.add(_amount);
        }
        if (rewardEligible) {
            user.amount = user.amount.add(user.pendingAmount).add(_amount);
            pool.rewardEligibleSupply = pool.rewardEligibleSupply.add(_amount);
            user.pendingAmount = 0;
        } else {
            user.pendingAmount = user.pendingAmount.add(_amount);
        }
        if (claimEligible && rewardEligible) {
            user.rewardDebt = user.amount.mul(pool.accRewardPerShare).div(1e12);
        }
        IVANN(vAnn).mint(msg.sender, _amount.mul(VANN_RATE));
        user.depositedDate = block.timestamp;
        user.boostedDate = block.timestamp;
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from AnnexFarm.
    function withdraw(uint256 _pid, uint256 _amount) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount + user.pendingAmount >= _amount, "withdraw: not good");
        require(block.timestamp - user.depositedDate > unstakableTime, "not eligible to undtake");
        // updatePool(_pid);
        _claimBaseRewards(_pid, msg.sender);
        if (user.amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.rewardEligibleSupply = pool.rewardEligibleSupply.sub(_amount);
        } else {
            user.pendingAmount = user.pendingAmount.sub(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accRewardPerShare).div(1e12);
        if (annex == address(pool.lpToken)) {
            lpSupplyOfAnnPool = lpSupplyOfAnnPool.sub(_amount);
        }
        IVANN(vAnn).burnFrom(msg.sender, _amount.mul(VANN_RATE));
        pool.lpToken.safeTransfer(address(msg.sender), _amount);
        user.depositedDate = block.timestamp;
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // transfer VANN
    function move(uint256 _pid, address _sender, address _recipient, uint256 _vannAmount) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage sender = userInfo[_pid][_sender];
        UserInfo storage recipient = userInfo[_pid][_recipient];

        uint256 amount = _vannAmount.div(VANN_RATE);

        require(sender.amount + sender.pendingAmount >= amount, "transfer exceeds amount");
        require(block.timestamp - sender.depositedDate > unstakableTime, "not eligible to undtake");

        _claimBaseRewards(_pid, _sender);

        if (sender.amount > 0) {
            sender.amount = sender.amount.sub(amount);
        } else {
            sender.pendingAmount = sender.pendingAmount.sub(amount);
        }
        sender.rewardDebt = sender.amount.mul(pool.accRewardPerShare).div(1e12);
        sender.depositedDate = block.timestamp;

        bool claimEligible = checkRewardClaimEligible(recipient.depositedDate);
        bool rewardEligible = checkRewardEligible(recipient.boostFactors.length);

        if (claimEligible && rewardEligible) {
            _claimBaseRewards(_pid, _recipient);
        }

        if (rewardEligible) {
            recipient.amount = recipient.amount.add(recipient.pendingAmount).add(amount);
            recipient.pendingAmount = 0;
        } else {
            recipient.pendingAmount = recipient.pendingAmount.add(amount);
        }
        if (claimEligible && rewardEligible) {
            recipient.rewardDebt = recipient.amount.mul(pool.accRewardPerShare).div(1e12);
        }
        recipient.depositedDate = block.timestamp;
        recipient.boostedDate = block.timestamp;
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount.add(user.pendingAmount));
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        if (user.amount > 0) {
            pool.rewardEligibleSupply = pool.rewardEligibleSupply.sub(user.amount);
        }
        user.amount = 0;
        user.pendingAmount = 0;
        user.rewardDebt = 0;
        user.boostRewardDebt = 0;
        user.accBoostReward = 0;
    }

    // Safe rewardToken transfer function, just in case if rounding error causes pool to not have enough ANNs.
    function safeRewardTransfer(address _to, uint256 _amount) internal {
        uint256 availableBal = IERC20(rewardToken).balanceOf(address(this));

        // Protect users liquidity
        if (annex == rewardToken) {
            if (availableBal > lpSupplyOfAnnPool) {
                availableBal = availableBal - lpSupplyOfAnnPool;
            } else {
                availableBal = 0;
            }
        }

        if (_amount > availableBal) {
            IERC20(rewardToken).transfer(_to, availableBal);
        } else {
            IERC20(rewardToken).transfer(_to, _amount);
        }
    }

    function updateInitialBoostMultiplier(uint _initialBoostMultiplier) external onlyOwner {
        initialBoostMultiplier = _initialBoostMultiplier;
    }

    function updatedBoostMultiplierFactor(uint _boostMultiplierFactor) external onlyOwner {
        boostMultiplierFactor = _boostMultiplierFactor;
    }

    // Update reward token address by owner.
    function updateRewardToken(address _reward) external onlyOwner {
        rewardToken = _reward;
    }

    // Update claimBaseRewardTime
    function updateClaimBaseRewardTime(uint256 _claimBaseRewardTime) external onlyOwner {
        claimBaseRewardTime = _claimBaseRewardTime;
    }

    // Update unstakableTime
    function updateUnstakableTime(uint256 _unstakableTime) external onlyOwner {
        unstakableTime = _unstakableTime;
    }

    // NFT Boosting

    // View function to see pending ANNs on frontend.
    function pendingBoostReward(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accRewardPerShare = pool.accRewardPerShare;

        if (block.number > pool.lastRewardBlock && pool.rewardEligibleSupply > 0) {
            uint256 multiplier =
                getMultiplier(pool.lastRewardBlock, block.number);
            uint256 reward =
                multiplier.mul(rewardPerBlock).mul(pool.allocPoint).div(
                    totalAllocPoint
                );
            accRewardPerShare = accRewardPerShare.add(
                reward.mul(1e12).div(pool.rewardEligibleSupply)
            );
        }

        uint256 boostMultiplier = getBoostMultiplier(user.boostFactors.length);
        uint256 baseReward = user.amount.mul(accRewardPerShare).div(1e12).sub(user.rewardDebt);
        uint256 boostReward = boostMultiplier.mul(baseReward);
        return user.accBoostReward.sub(user.boostRewardDebt).add(boostReward).div(100);
    }

    function getTotalPendingBoostRewards() external view returns (uint256) {
        uint256 totalRewards;
        for (uint i; i < poolInfo.length; i++) {
            PoolInfo storage pool = poolInfo[i];
            uint256 accRewardPerShare = pool.accRewardPerShare;

            for (uint j; j < boostedUsers[i].length; j++) {
                UserInfo storage user = userInfo[i][boostedUsers[i][j]];

                if (block.number > pool.lastRewardBlock && pool.rewardEligibleSupply > 0) {
                    uint256 multiplier =
                        getMultiplier(pool.lastRewardBlock, block.number);
                    uint256 reward =
                        multiplier.mul(rewardPerBlock).mul(pool.allocPoint).div(
                            totalAllocPoint
                        );
                    accRewardPerShare = accRewardPerShare.add(
                        reward.mul(1e12).div(pool.rewardEligibleSupply)
                    );
                }
                uint256 boostMultiplier = getBoostMultiplier(user.boostFactors.length);
                uint256 baseReward = user.amount.mul(accRewardPerShare).div(1e12).sub(user.rewardDebt);
                uint256 initBoostReward = boostMultiplier.mul(baseReward);
                uint256 boostReward = user.accBoostReward.sub(user.boostRewardDebt).add(initBoostReward).div(100);
                totalRewards = totalRewards.add(boostReward);
            }
        }

        return totalRewards;
    }

    function getClaimablePendingBoostRewards() external view returns (uint256) {
        uint256 totalRewards;
        for (uint i; i < poolInfo.length; i++) {
            PoolInfo storage pool = poolInfo[i];
            uint256 accRewardPerShare = pool.accRewardPerShare;

            for (uint j; j < boostedUsers[i].length; j++) {
                UserInfo storage user = userInfo[i][boostedUsers[i][j]];

                if (block.number - user.boostedDate >= claimBoostRewardTime) {
                    if (block.number > pool.lastRewardBlock && pool.rewardEligibleSupply > 0) {
                        uint256 multiplier =
                            getMultiplier(pool.lastRewardBlock, block.number);
                        uint256 reward =
                            multiplier.mul(rewardPerBlock).mul(pool.allocPoint).div(
                                totalAllocPoint
                            );
                        accRewardPerShare = accRewardPerShare.add(
                            reward.mul(1e12).div(pool.rewardEligibleSupply)
                        );
                    }
                    uint256 boostMultiplier = getBoostMultiplier(user.boostFactors.length);
                    uint256 baseReward = user.amount.mul(accRewardPerShare).div(1e12).sub(user.rewardDebt);
                    uint256 initBoostReward = boostMultiplier.mul(baseReward);
                    uint256 boostReward = user.accBoostReward.sub(user.boostRewardDebt).add(initBoostReward).div(100);
                    totalRewards = totalRewards.add(boostReward);
                }
            }
        }

        return totalRewards;
    }

    // Claim boost reward
    function claimBoostReward(uint256 _pid) external {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(block.timestamp - user.boostedDate > claimBoostRewardTime, "not eligible to claim");
        uint256 accRewardPerShare = pool.accRewardPerShare;

        if (block.number > pool.lastRewardBlock && pool.rewardEligibleSupply > 0) {
            uint256 multiplier =
                getMultiplier(pool.lastRewardBlock, block.number);
            uint256 reward =
                multiplier.mul(rewardPerBlock).mul(pool.allocPoint).div(
                    totalAllocPoint
                );
            accRewardPerShare = accRewardPerShare.add(
                reward.mul(1e12).div(pool.rewardEligibleSupply)
            );
        }

        uint256 boostMultiplier = getBoostMultiplier(user.boostFactors.length);
        uint256 baseReward = user.amount.mul(accRewardPerShare).div(1e12).sub(user.rewardDebt);
        uint256 boostReward = boostMultiplier.mul(baseReward);
        safeRewardTransfer(msg.sender, user.accBoostReward.sub(user.boostRewardDebt).add(boostReward));
        user.boostRewardDebt = user.boostRewardDebt.add(boostReward);
        user.boostedDate = block.timestamp;
    }

    function _boost(uint256 _pid, uint _tokenId) internal {
        require (isBoosted[_tokenId] == false, "already boosted");

        boostFactor.transferFrom(msg.sender, address(this), _tokenId);
        boostFactor.updateStakeTime(_tokenId, true);

        isBoosted[_tokenId] = true;

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        if (user.pendingAmount > 0) {
            user.amount = user.pendingAmount;
            pool.rewardEligibleSupply = pool.rewardEligibleSupply.add(user.amount);
            user.pendingAmount = 0;
        }
        user.boostFactors.push(_tokenId);
        pool.totalBoostCount = pool.totalBoostCount + 1;

        emit Boost(msg.sender, _pid, _tokenId);
    }

    function boost(uint256 _pid, uint _tokenId) external {
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount + user.pendingAmount > 0, "no stake tokens");
        require(user.boostFactors.length + 1 <= maximumBoostCount);
        // PoolInfo storage pool = poolInfo[_pid];
        if (user.boostFactors.length == 0) {
            boostedUsers[_pid].push(msg.sender);
        }
        bool claimEligible = checkRewardClaimEligible(user.depositedDate);
        // updatePool(_pid);
        if (claimEligible) {
            _claimBaseRewards(_pid, msg.sender);
        }
        _boost(_pid, _tokenId);
        user.boostedDate = block.timestamp;
    }

    function boostPartially(uint _pid, uint tokenAmount) external {
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount + user.pendingAmount > 0, "no stake tokens");
        require(user.boostFactors.length + tokenAmount <= maximumBoostCount);
        // PoolInfo storage pool = poolInfo[_pid];
        if (user.boostFactors.length == 0) {
            boostedUsers[_pid].push(msg.sender);
        }
        uint256 ownerTokenCount = boostFactor.balanceOf(msg.sender);
        require(tokenAmount <= ownerTokenCount);
        bool claimEligible = checkRewardClaimEligible(user.depositedDate);
        // updatePool(_pid);
        if (claimEligible) {
            _claimBaseRewards(_pid, msg.sender);
        }

        do {
            tokenAmount--;
            uint _tokenId = boostFactor.tokenOfOwnerByIndex(msg.sender, tokenAmount);

            _boost(_pid, _tokenId);
        } while (tokenAmount > 0);
        user.boostedDate = block.timestamp;
    }

    function boostAll(uint _pid) external {
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount + user.pendingAmount > 0, "no stake tokens");
        uint256 ownerTokenCount = boostFactor.balanceOf(msg.sender);
        require(ownerTokenCount > 0, "");
        // PoolInfo storage pool = poolInfo[_pid];
        if (user.boostFactors.length == 0) {
            boostedUsers[_pid].push(msg.sender);
        }
        uint256 tokenAmount = maximumBoostCount - user.boostFactors.length;
        if (ownerTokenCount < tokenAmount) {
            tokenAmount = ownerTokenCount;
        }
        bool claimEligible = checkRewardClaimEligible(user.depositedDate);
        // updatePool(_pid);
        if (claimEligible) {
            _claimBaseRewards(_pid, msg.sender);
        }

        do {
            tokenAmount--;
            uint _tokenId = boostFactor.tokenOfOwnerByIndex(msg.sender, tokenAmount);

            _boost(_pid, _tokenId);
        } while (tokenAmount > 0);
        user.boostedDate = block.timestamp;
    }

    function _unBoost(uint _pid, uint _tokenId) internal {
        require (isBoosted[_tokenId] == true);

        boostFactor.transferFrom(address(this), msg.sender, _tokenId);
        boostFactor.updateStakeTime(_tokenId, false);

        isBoosted[_tokenId] = false;

        emit UnBoost(msg.sender, _pid, _tokenId);
    }

    function unBoostPartially(uint _pid, uint tokenAmount) external {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.boostFactors.length > 0, "");
        require(tokenAmount <= user.boostFactors.length, "");

        bool claimEligible = checkRewardClaimEligible(user.depositedDate);
        // updatePool(_pid);
        if (claimEligible) {
            _claimBaseRewards(_pid, msg.sender);
        }
        for (uint i; i < tokenAmount; i++) {
            uint index = user.boostFactors.length - 1;
            uint _tokenId = user.boostFactors[index];

            _unBoost(_pid, _tokenId);
            user.boostFactors.pop();
            pool.totalBoostCount = pool.totalBoostCount + 1;
        }
        user.boostedDate = block.timestamp;

        if (user.boostFactors.length == 0) {
            user.pendingAmount = user.amount;
            user.amount = 0;
            pool.rewardEligibleSupply = pool.rewardEligibleSupply.sub(user.pendingAmount);

            uint index;
            for (uint j; j < boostedUsers[_pid].length; j++) {
                if (address(msg.sender) == address(boostedUsers[_pid][j])) {
                    index = j;
                    break;
                }
            }
            boostedUsers[_pid][index] = boostedUsers[_pid][boostedUsers[_pid].length - 1];
            boostedUsers[_pid].pop();
        }
    }

    function unBoostAll(uint _pid) external {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.boostFactors.length > 0, "");

        bool claimEligible = checkRewardClaimEligible(user.depositedDate);
        // updatePool(_pid);
        if (claimEligible) {
            _claimBaseRewards(_pid, msg.sender);
        }
        do {
            uint index = user.boostFactors.length - 1;
            uint _tokenId = user.boostFactors[index];

            _unBoost(_pid, _tokenId);
            user.boostFactors.pop();
            pool.totalBoostCount = pool.totalBoostCount + 1;
        } while (user.boostFactors.length > 0);
        user.boostedDate = block.timestamp;

        if (user.boostFactors.length == 0) {
            user.pendingAmount = user.amount;
            user.amount = 0;
            pool.rewardEligibleSupply = pool.rewardEligibleSupply.sub(user.pendingAmount);

            uint index;
            for (uint j; j < boostedUsers[_pid].length; j++) {
                if (address(msg.sender) == address(boostedUsers[_pid][j])) {
                    index = j;
                    break;
                }
            }
            boostedUsers[_pid][index] = boostedUsers[_pid][boostedUsers[_pid].length - 1];
            boostedUsers[_pid].pop();
        }
    }

    // Update boostFactor address. Can only be called by the owner.
    function setBoostFactor(
        address _address
    ) external onlyOwner {
        boostFactor = IBoostToken(_address);
    }

    // Update claimBoostRewardTime
    function updateClaimBoostRewardTime(uint256 _claimBoostRewardTime) external onlyOwner {
        claimBoostRewardTime = _claimBoostRewardTime;
    }

    // Update minimum valid boost token count. Can only be called by the owner.
    function updateMinimumValidBoostCount(uint16 _count) external onlyOwner {
        minimumValidBoostCount = _count;
    }

    // Update maximum valid boost token count. Can only be called by the owner.
    function updateMaximumBoostCount(uint16 _count) external onlyOwner {
        maximumBoostCount = _count;
    }

    // Withdraw NFTs which transferred unexpectedly
    function emergencyNftWithdraw() external nonReentrant onlyOwner {
        uint256 ownerTokenCount = boostFactor.balanceOf(address(this));

        for (uint256 i; i < ownerTokenCount; i++) {
            uint _tokenId = boostFactor.tokenOfOwnerByIndex(address(this), i);

            boostFactor.safeTransferFrom(address(this), msg.sender, _tokenId);
        }
    }
}
