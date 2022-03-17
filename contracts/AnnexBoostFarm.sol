// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./interfaces/IBoostToken.sol";
import "./interfaces/IERC721Receiver.sol";
import "./interfaces/IERC20.sol";
import "./libraries/SafeERC20.sol";
import "./libraries/EnumerableSet.sol";
import "./libraries/SafeMath.sol";
import "./libraries/Ownable.sol";
import "./libraries/ReentrancyGuard.sol";

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
    }
    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. ANNs to distribute per block.
        uint256 lastRewardBlock; // Last block number that ANNs distribution occurs.
        uint256 accRewardPerShare; // Accumulated ANNs per share, times 1e12. See below.
        uint256 totalValidBoostNum; // Total valid boosted factor count.
        uint256 totalValidBoostCount; // Total valid boosted accounts count.
        uint256 accBoostRewardPerShare; // Accumulated ANNs per share,.
    }
    // The Annex TOKEN!
    address public annex;
    // The Reward TOKEN!
    address public rewardToken;
    // Block number when bonus ANN period ends.
    uint256 public bonusEndBlock;
    // ANN tokens created per block.
    uint256 public rewardPerBlock;
    // Bonus muliplier for early annex makers.
    uint256 public constant BONUS_MULTIPLIER = 10;
    // Info of each pool.
    PoolInfo[] private poolInfo;
    // Total ANN amount deposited in ANN single pool. To reduce tx-fee, not included in struct PoolInfo.
    uint256 private lpSupplyOfAnnPool;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // claimable time limit for base reward
    uint256 public claimRewardTime = 86400;
    uint256 public unstakableTime = 172800;

    // Boosting Part
    // ANN tokens distribution for boosting per block.
    uint256 public boostRewardPerBlock;
    // Minimum vaild boost NFT count
    uint16 public minimumValidBoostCount = 1;
    // Maximum boost NFT count
    uint16 public maximumBoostCount = 10;
    // NFT contract for boosting
    IBoostToken public boostFactor;
    // Boosted with NFT or not
    mapping (uint256 => bool) public isBoosted;
    // boostFactor list per address
    mapping (address => uint[]) public boostFactors;
    // claimable time limit for boost reward
    uint256 public claimBoostRewardTime = 86400 * 30;

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
        address _rewardToken
        address _boost,
        uint256 _rewardPerBlock,
        uint256 _boostRewardPerBlock,
        uint256 _startBlock,
        uint256 _bonusEndBlock
    ) public {
        annex = _annex;
        rewardToken = _rewardToken;
        boostFactor = IBoostToken(_boost);
        rewardPerBlock = _rewardPerBlock;
        boostRewardPerBlock = _boostRewardPerBlock;
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
        uint totalValidBoostNum,
        uint totalValidBoostCount,
        uint accBoostRewardPerShare
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
            pool.totalValidBoostNum,
            pool.totalValidBoostCount,
            pool.accBoostRewardPerShare
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
                accBoostRewardPerShare: 0,
                totalValidBoostNum: 0,
                totalValidBoostCount: 0
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

    // View function to see pending ANNs on frontend.
    function pendingReward(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accRewardPerShare = pool.accRewardPerShare;
        uint256 accBoostRewardPerShare = pool.accBoostRewardPerShare;
        uint256 lpSupply;
        if (annex == address(pool.lpToken)) {
            lpSupply = lpSupplyOfAnnPool;
        } else {
            lpSupply = pool.lpToken.balanceOf(address(this));
        }
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier =
                getMultiplier(pool.lastRewardBlock, block.number);
            uint256 reward =
                multiplier.mul(rewardPerBlock).mul(pool.allocPoint).div(
                    totalAllocPoint
                );
            accRewardPerShare = accRewardPerShare.add(
                reward.mul(1e12).div(lpSupply)
            );

            uint256 boostReward =
                multiplier.mul(boostRewardPerBlock).mul(pool.allocPoint).div(
                    totalAllocPoint
                );
            if (pool.totalValidBoostNum - minimumValidBoostCount * pool.totalValidBoostCount > 0) {
                accBoostRewardPerShare = accBoostRewardPerShare.add(
                    boostReward.mul(1e12).div(pool.totalValidBoostNum - minimumValidBoostCount * pool.totalValidBoostCount)
                );
            }
        }
        uint256 reward = user.amount.mul(accRewardPerShare).div(1e12).sub(user.rewardDebt);
        uint256 validBoostFactors = getValidBoostFactors(user.boostFactors.length);
        uint256 boostReward = validBoostFactors.mul(accBoostRewardPerShare).div(1e12).sub(user.boostRewardDebt);
        uint256 totalReward = reward.add(boostReward);
        return totalReward;
    }

    // View function to see pending ANNs on frontend.
    function pendingDepositedReward(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accRewardPerShare = pool.accRewardPerShare;
        uint256 lpSupply;
        if (annex == address(pool.lpToken)) {
            lpSupply = lpSupplyOfAnnPool;
        } else {
            lpSupply = pool.lpToken.balanceOf(address(this));
        }
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier =
                getMultiplier(pool.lastRewardBlock, block.number);
            uint256 reward =
                multiplier.mul(rewardPerBlock).mul(pool.allocPoint).div(
                    totalAllocPoint
                );
            accRewardPerShare = accRewardPerShare.add(
                reward.mul(1e12).div(lpSupply)
            );
        }

        return user.amount.mul(accRewardPerShare).div(1e12).sub(user.rewardDebt);
    }

    // View function to see pending ANNs on frontend.
    function pendingBoostingReward(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accBoostRewardPerShare = pool.accBoostRewardPerShare;
        uint256 lpSupply;
        if (annex == address(pool.lpToken)) {
            lpSupply = lpSupplyOfAnnPool;
        } else {
            lpSupply = pool.lpToken.balanceOf(address(this));
        }
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier =
                getMultiplier(pool.lastRewardBlock, block.number);

            uint256 boostReward =
                multiplier.mul(boostRewardPerBlock).mul(pool.allocPoint).div(
                    totalAllocPoint
                );
            if (pool.totalValidBoostNum - minimumValidBoostCount * pool.totalValidBoostCount > 0) {
                accBoostRewardPerShare = accBoostRewardPerShare.add(
                    boostReward.mul(1e12).div(pool.totalValidBoostNum - minimumValidBoostCount * pool.totalValidBoostCount)
                );
            }
        }
        uint256 validBoostFactors = getValidBoostFactors(user.boostFactors.length);
        return validBoostFactors.mul(accBoostRewardPerShare).div(1e12).sub(user.boostRewardDebt);
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
        uint256 lpSupply;
        if (annex == address(pool.lpToken)) {
            lpSupply = lpSupplyOfAnnPool;
        } else {
            lpSupply = pool.lpToken.balanceOf(address(this));
        }
        if (lpSupply == 0 || pool.totalValidBoostCount == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 reward =
            multiplier.mul(rewardPerBlock).mul(pool.allocPoint).div(
                totalAllocPoint
            );
        pool.accRewardPerShare = pool.accRewardPerShare.add(
            reward.mul(1e12).div(lpSupply)
        );

        uint256 boostReward =
            multiplier.mul(boostRewardPerBlock).mul(pool.allocPoint).div(
                totalAllocPoint
            );
        if (pool.totalValidBoostNum - minimumValidBoostCount * pool.totalValidBoostCount > 0) {
            pool.accBoostRewardPerShare = pool.accBoostRewardPerShare.add(
                boostReward.mul(1e12).div(pool.totalValidBoostNum - minimumValidBoostCount * pool.totalValidBoostCount)
            );
        }
        pool.lastRewardBlock = block.number;
    }

    // Check the eligible user or not for reward
    function checkRewardEligible(uint boost) internal returns(bool) {
        if (boost >= minimumValidBoostCount) {
            return true;
        }

        return false;
    }

    // Check claim eligible
    function checkRewardClaimEligible(uint depositedTime) internal returns(bool) {
        if (block.timestamp - depositedTime > claimRewardTime) {
            return true;
        }

        return false;
    }

    // Claim base lp reward
    function claimBaseReward(uint256 _pid) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        bool claimEligible = checkRewardClaimEligible(user.depositedDate);

        if (user.amount > 0 && claimEligible) {
            uint256 pending =
                user.amount.mul(pool.accRewardPerShare).div(1e12).sub(
                    user.rewardDebt
                );
            safeRewardTransfer(msg.sender, pending);
        }
    }

    // Deposit LP tokens to Annexswap for ANN allocation.
    function deposit(uint256 _pid, uint256 _amount) external {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        bool claimEligible = checkRewardClaimEligible(user.depositedDate);
        if (user.amount > 0 && claimEligible) {
            uint256 pending =
                user.amount.mul(pool.accRewardPerShare).div(1e12).sub(
                    user.rewardDebt
                );
            safeRewardTransfer(msg.sender, pending);
        }
        pool.lpToken.safeTransferFrom(
            address(msg.sender),
            address(this),
            _amount
        );
        if (annex == address(pool.lpToken)) {
            lpSupplyOfAnnPool = lpSupplyOfAnnPool.add(_amount);
        }
        if (checkRewardEligible(user.boostFactors.length)) {
            user.amount = user.amount.add(_amount);
        } else {
            user.pendingAmount = user.pendingAmount.add(_amount);
        }
        if (claimEligible) {
            user.rewardDebt = user.amount.mul(pool.accRewardPerShare).div(1e12);
        }
        user.depositedDate = block.timestamp;
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from AnnexFarm.
    function withdraw(uint256 _pid, uint256 _amount) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        require(block.timestamp - user.depositedDate > unstakableTime, "not eligible to undtake");
        updatePool(_pid);
        uint256 pending =
            user.amount.mul(pool.accRewardPerShare).div(1e12).sub(
                user.rewardDebt
            );
        safeRewardTransfer(msg.sender, pending);
        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accRewardPerShare).div(1e12);
        if (annex == address(pool.lpToken)) {
            lpSupplyOfAnnPool = lpSupplyOfAnnPool.sub(_amount);
        }
        pool.lpToken.safeTransfer(address(msg.sender), _amount);
        user.depositedDate = block.timestamp;
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
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

    // Update reward token address by owner.
    function updateRewardToken(address _reward) public onlyOwner {
        rewardToken = _reward;
    }

    // Update claimRewardTime
    function updateClaimRewardTime(uint256 _claimRewardTime) external onlyOwner {
        claimRewardTime = _claimRewardTime;
    }

    // Update unstakableTime
    function updateUnstakableTime(uint256 _unstakableTime) external onlyOwner {
        unstakableTime = _unstakableTime;
    }

    // NFT Boosting

    // Update the given reward per block. Can only be called by the owner.
    function setBoostRewardPerBlock(
        uint256 speed
    ) public onlyOwner {
        boostRewardPerBlock = speed;
    }

    function _boost(uint256 _pid, uint _tokenId) internal {
        require (isBoosted[_tokenId] == false, "already boosted");

        boostFactor.transferFrom(msg.sender, address(this), _tokenId);
        boostFactor.updateStakeTime(_tokenId, true);

        isBoosted[_tokenId] = true;

        UserInfo storage user = userInfo[_pid][msg.sender];
        uint originBoostFactors = user.boostFactors.length;
        user.boostFactors.push(_tokenId);

        PoolInfo storage pool = poolInfo[_pid];
        if (user.boostFactors.length > minimumValidBoostCount && originBoostFactors <= minimumValidBoostCount) {
            pool.totalValidBoostCount++;
            pool.totalValidBoostNum = pool.totalValidBoostNum + user.boostFactors.length;
        } else if (originBoostFactors > minimumValidBoostCount) {
            pool.totalValidBoostNum++;
        }

        emit Boost(msg.sender, _pid, _tokenId);
    }

    function boost(uint256 _pid, uint _tokenId) external {
        _claimRewards(_pid, msg.sender);
        _boost(_pid, _tokenId);
        _updateUserDebt(_pid, msg.sender);
    }

    function boostPartially(uint _pid, uint tokenAmount) external {
        _claimRewards(_pid, msg.sender);
        uint256 ownerTokenCount = boostFactor.balanceOf(msg.sender);
        require(tokenAmount <= ownerTokenCount);

        do {
            tokenAmount--;
            uint _tokenId = boostFactor.tokenOfOwnerByIndex(msg.sender, tokenAmount);

            _boost(_pid, _tokenId);
        } while (tokenAmount > 0);
        _updateUserDebt(_pid, msg.sender);
    }

    function boostAll(uint _pid) external {
        _claimRewards(_pid, msg.sender);
        uint256 ownerTokenCount = boostFactor.balanceOf(msg.sender);
        require(ownerTokenCount > 0, "");

        do {
            uint _tokenId = boostFactor.tokenOfOwnerByIndex(msg.sender, ownerTokenCount - 1);

            _boost(_pid, _tokenId);
            ownerTokenCount = boostFactor.balanceOf(msg.sender);
        } while (ownerTokenCount > 0);

        _updateUserDebt(_pid, msg.sender);
    }

    function _unBoost(uint _pid, uint _tokenId) internal {
        require (isBoosted[_tokenId] == true);

        boostFactor.transferFrom(address(this), msg.sender, _tokenId);
        boostFactor.updateStakeTime(_tokenId, false);

        isBoosted[_tokenId] = false;

        UserInfo storage user = userInfo[_pid][msg.sender];
        PoolInfo storage pool = poolInfo[_pid];
        uint length = user.boostFactors.length;
        if (length > minimumValidBoostCount && length - 1 <= minimumValidBoostCount) {
            pool.totalValidBoostCount--;
            pool.totalValidBoostNum = pool.totalValidBoostNum - length;
        } else if (length - 1 > minimumValidBoostCount) {
            pool.totalValidBoostNum--;
        }

        emit UnBoost(msg.sender, _pid, _tokenId);
    }

    function unBoostPartially(uint _pid, uint tokenAmount) external {
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.boostFactors.length > 0, "");
        require(tokenAmount <= user.boostFactors.length, "");

        _claimRewards(_pid, msg.sender);

        for (uint i; i < tokenAmount; i++) {
            uint index = user.boostFactors.length - 1;
            uint _tokenId = user.boostFactors[index];

            _unBoost(_pid, _tokenId);
            user.boostFactors.pop();
        }
        _updateUserDebt(_pid, msg.sender);
    }

    function unBoostAll(uint _pid) external {
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.boostFactors.length > 0, "");

        _claimRewards(_pid, msg.sender);

        do {
            uint index = user.boostFactors.length - 1;
            uint _tokenId = user.boostFactors[index];

            _unBoost(_pid, _tokenId);
            user.boostFactors.pop();
        } while (user.boostFactors.length > 0);
        _updateUserDebt(_pid, msg.sender);
    }

    function _claimRewards(uint256 _pid, address _user) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        require(user.amount > 0, "No deposited lptokens");
        updatePool(_pid);
        uint256 validBoostFactors = getValidBoostFactors(user.boostFactors.length);

        uint256 pending =
            user.amount.mul(pool.accRewardPerShare).div(1e12).sub(
                user.rewardDebt
            );
        uint256 boostPending = validBoostFactors.mul(pool.accBoostRewardPerShare).div(1e12).sub(user.boostRewardDebt);
        safeRewardTransfer(_user, pending.add(boostPending));
    }

    function _updateUserDebt(uint256 _pid, address _user) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 validBoostFactors = getValidBoostFactors(user.boostFactors.length);
        user.rewardDebt = user.amount.mul(pool.accRewardPerShare).div(1e12);
        user.boostRewardDebt = validBoostFactors.mul(pool.accBoostRewardPerShare).div(1e12);
    }

    function checkOriginOwner(uint _pid, address _user, uint _tokenId) internal view returns (bool) {
        UserInfo storage user = userInfo[_pid][_user];

        bool owner = false;
        for (uint i; i < user.boostFactors.length; i++) {
            if (_tokenId == user.boostFactors[i]) {
                owner = true;
                break;
            }
        }

        return owner;
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
