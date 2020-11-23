// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./BearnToken.sol";

// BearnChef is the master of BFI and he is a fair guy.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
//
// Note that this pool has no minter key as the original MasterChef of Sushi.
// Instead, weekly the governance will mint BFI and send reward to this pool.
contract BearnChef is Ownable {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint amount;     // How many LP tokens the user has provided.
        uint rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of BFIs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accBfiPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accBfiPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
        uint accumulatedStakingPower; // will accumulate every time user harvest
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint allocPoint;       // How many allocation points assigned to this pool. BFIs to distribute per block.
        uint lastRewardBlock;  // Last block number that BFIs distribution occurs.
        uint accBfiPerShare; // Accumulated BFIs per share, times 1e12. See below.
        bool isStarted; // if lastRewardBlock has passed
    }

    // The BFI TOKEN!
    BFI public bfi;

    // BFI tokens created per block.
    uint public bfiPerBlock;

    // Info of each pool.
    PoolInfo[] public poolInfo;

    // Info of each user that stakes LP tokens.
    mapping (uint => mapping (address => UserInfo)) public userInfo;

    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint public totalAllocPoint = 0;

    // The block number when BFI mining starts.
    uint public startBlock;

    uint public constant BLOCKS_PER_WEEK = 46500;

    event Deposit(address indexed user, uint indexed pid, uint amount);
    event Withdraw(address indexed user, uint indexed pid, uint amount);
    event EmergencyWithdraw(address indexed user, uint indexed pid, uint amount);

    constructor(
        BFI _bfi,
        uint _bfiPerBlock,
        uint _startBlock
    ) public {
        bfi = _bfi;
        bfiPerBlock = _bfiPerBlock; // supposed to be 0.001 (1e16 wei)
        startBlock = _startBlock; // supposed to be 10,883,800 (Fri Sep 18 2020 3:00:00 GMT+0)
    }

    function poolLength() external view returns (uint) {
        return poolInfo.length;
    }

    function setBfiPerBlock(uint _bfiPerBlock) public onlyOwner {
        massUpdatePools();
        bfiPerBlock = _bfiPerBlock;
    }

    function checkPoolDuplicate(IERC20 _lpToken) internal view {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            require(poolInfo[pid].lpToken != _lpToken, "add: existing pool?");
        }
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint _allocPoint, IERC20 _lpToken, bool _withUpdate, uint _lastRewardBlock) public onlyOwner {
        checkPoolDuplicate(_lpToken);
        if (_withUpdate) {
            massUpdatePools();
        }
        if (block.number < startBlock) {
            // chef is sleeping
            if (_lastRewardBlock == 0) {
                _lastRewardBlock = startBlock;
            } else {
                if (_lastRewardBlock < startBlock) {
                    _lastRewardBlock = startBlock;
                }
            }
        } else {
            // chef is cooking
            if (_lastRewardBlock == 0 || _lastRewardBlock < block.number) {
                _lastRewardBlock = block.number;
            }
        }
        bool _isStarted = (_lastRewardBlock <= startBlock) || (_lastRewardBlock <= block.number);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: _lastRewardBlock,
            accBfiPerShare: 0,
            isStarted: _isStarted
        }));
        if (_isStarted) {
            totalAllocPoint = totalAllocPoint.add(_allocPoint);
        }
    }

    // Update the given pool's BFI allocation point. Can only be called by the owner.
    function set(uint _pid, uint _allocPoint) public onlyOwner {
        massUpdatePools();
        PoolInfo storage pool = poolInfo[_pid];
        if (pool.isStarted) {
            totalAllocPoint = totalAllocPoint.sub(pool.allocPoint).add(_allocPoint);
        }
        pool.allocPoint = _allocPoint;
    }

    // View function to see pending BFIs on frontend.
    function pendingBearn(uint _pid, address _user) external view returns (uint) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint accBfiPerShare = pool.accBfiPerShare;
        uint lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint _numBlocks = block.number.sub(pool.lastRewardBlock);
            if (totalAllocPoint > 0) {
                uint _bfiReward = _numBlocks.mul(bfiPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
                accBfiPerShare = accBfiPerShare.add(_bfiReward.mul(1e12).div(lpSupply));
            }
        }
        return user.amount.mul(accBfiPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint length = poolInfo.length;
        for (uint pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        if (!pool.isStarted) {
            pool.isStarted = true;
            totalAllocPoint = totalAllocPoint.add(pool.allocPoint);
        }
        if (totalAllocPoint > 0) {
            uint _numBlocks = block.number.sub(pool.lastRewardBlock);
            uint _bfiReward = _numBlocks.mul(bfiPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            pool.accBfiPerShare = pool.accBfiPerShare.add(_bfiReward.mul(1e12).div(lpSupply));
        }
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to BearnChef for BFI allocation.
    function deposit(uint _pid, uint _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint pending = user.amount.mul(pool.accBfiPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                user.accumulatedStakingPower = user.accumulatedStakingPower.add(pending);
                safeBfiTransfer(msg.sender, pending);
            }
        }
        if(_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accBfiPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from BearnChef.
    function withdraw(uint _pid, uint _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint pending = user.amount.mul(pool.accBfiPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            user.accumulatedStakingPower = user.accumulatedStakingPower.add(pending);
            safeBfiTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accBfiPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    // Safe bfi transfer function, just in case if rounding error causes pool to not have enough BFIs.
    function safeBfiTransfer(address _to, uint _amount) internal {
        uint bfiBal = bfi.balanceOf(address(this));
        if (_amount > bfiBal) {
            bfi.transfer(_to, bfiBal);
        } else {
            bfi.transfer(_to, _amount);
        }
    }

    // This function allows governance to take unsupported tokens out of the contract. This is in an effort to make someone whole, should they seriously mess up.
    // There is no guarantee governance will vote to return these. It also allows for removal of airdropped tokens.
    function governanceRecoverUnsupported(IERC20 _token, uint amount, address to) external onlyOwner {
        if (block.number < startBlock + BLOCKS_PER_WEEK * 100) { // do not allow to drain lpToken if less than 2 years
            uint length = poolInfo.length;
            for (uint pid = 0; pid < length; ++pid) {
                PoolInfo storage pool = poolInfo[pid];
                // cant take staked asset
                require(_token != pool.lpToken, "!pool.lpToken");
            }
        }
        _token.safeTransfer(to, amount);
    }
}
