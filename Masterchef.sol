// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;
pragma abicoder v2;

import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/math/SafeMath.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/security/ReentrancyGuard.sol";



interface T8Referral {
    struct Referral {
        address parent_address;
        uint8 level;
        uint com_per;
    }
    function recordReferral(address user, address referrer, uint _packageId) external;
    function recordReferralCommission(address referrer, uint256 commission) external;
    function getReferrer(address user) external view returns (Referral[] memory);
}

interface TripleEight is IERC20 {
    function mint(address to, uint256 amount) external;

}

contract MasterChef is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20  for IERC20;

    ISwapRouter public immutable swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    address public constant WETH9 = 0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889;
    uint24 public constant poolFee = 3000;


    // Info of each user.
    struct UserInfo {
        uint256 amount;         // How many LP tokens the user has provided.
        uint256 rewardDebt;     // Reward debt. See explanation below.
        uint256 rewardLockedUp;  // Reward locked up.
        uint256 nextHarvestUntil; // When can the user harvest again.
        //
        // We do some fancy math here. Basically, any point in time, the amount of 888
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accLionPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accLionPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. 888 to distribute per second.
        uint256 lastRewardTime;  // Last block time that 888 distribution occurs.
        uint256 accTokenPerShare;   // Accumulated 888 per share, 
        uint16 depositFeeBP;      // Deposit fee in basis points
        uint256 harvestInterval;  // Harvest interval in seconds
    }

    // The 888 TOKEN!
    TripleEight public myToken;
    // Dev address.
    address public devAddress;
    // Deposit Fee address
    address public feeAddress;
    // 888 tokens created per second.
    uint256 public tokenPerSecond;
    // Bonus muliplier for early lion makers.
    uint256 public constant BONUS_MULTIPLIER = 1;
    // Max harvest interval: 14 days.
    uint256 public constant MAXIMUM_HARVEST_INTERVAL = 14 days;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block time when 888 mining starts.
    uint256 public startTime;
    // Total locked up rewards
    uint256 public totalLockedUpRewards;

    // 888 referral contract address.
    T8Referral public T8ReferralContract;
    // Referral commission rate in basis points.
    // uint16 public referralCommissionRate = 300;
    // Max referral commission rate: 10%.
    // uint16 public constant MAXIMUM_REFERRAL_COMMISSION_RATE = 1000;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmissionRateUpdated(address indexed caller, uint256 previousAmount, uint256 newAmount);
    event ReferralCommissionPaid(address indexed user, address indexed referrer, uint256 commissionAmount);
    event RewardLockedUp(address indexed user, uint256 indexed pid, uint256 amountLockedUp);

    constructor(
        TripleEight _mytoken,
        uint256 _tokenPerSecond, 
        address _feeCollector
    )  {
        myToken = _mytoken;
        startTime = block.timestamp;
        tokenPerSecond = _tokenPerSecond;

        devAddress = msg.sender;
        feeAddress = _feeCollector;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, IERC20 _lpToken, uint16 _depositFeeBP, uint256 _harvestInterval, bool _withUpdate) public onlyOwner {
        require(_depositFeeBP <= 10000, "add: invalid deposit fee basis points");
        require(_harvestInterval <= MAXIMUM_HARVEST_INTERVAL, "add: invalid harvest interval");
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardTime = block.timestamp > startTime ? block.timestamp : startTime;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
        lpToken: _lpToken,
        allocPoint: _allocPoint,
        lastRewardTime: lastRewardTime,
        accTokenPerShare: 0,
        depositFeeBP: _depositFeeBP,
        harvestInterval: _harvestInterval
        }));
    }

    // Update the given pool's 888 allocation point and deposit fee. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, uint16 _depositFeeBP, uint256 _harvestInterval, bool _withUpdate) public onlyOwner {
        require(_depositFeeBP <= 10000, "set: invalid deposit fee basis points");
        require(_harvestInterval <= MAXIMUM_HARVEST_INTERVAL, "set: invalid harvest interval");
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].depositFeeBP = _depositFeeBP;
        poolInfo[_pid].harvestInterval = _harvestInterval;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256) {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    // View function to see pending 888 on frontend.
    function pendingToken(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accTokenPerShare = pool.accTokenPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.timestamp > pool.lastRewardTime && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
            uint256 tokenReward = multiplier.mul(tokenPerSecond).mul(pool.allocPoint).div(totalAllocPoint);
            accTokenPerShare = accTokenPerShare.add(tokenReward.mul(1e12).div(lpSupply)); // tokenReward.mul(1e12).div(lpSupply)
        }
        uint256 pending = user.amount.mul(accTokenPerShare).div(1e12).sub(user.rewardDebt);
        return pending.add(user.rewardLockedUp);
    }

    // View function to see if user can harvest 888.
    function canHarvest(uint256 _pid, address _user) public view returns (bool) {
        UserInfo storage user = userInfo[_pid][_user];
        return block.timestamp >= user.nextHarvestUntil;
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
        uint256 tokenReward = multiplier.mul(tokenPerSecond).mul(pool.allocPoint).div(totalAllocPoint);
        // lion.mint(devAddress, lionReward.div(10));
        myToken.mint(address(this), tokenReward);
        pool.accTokenPerShare = pool.accTokenPerShare.add(tokenReward.mul(1e12).div(lpSupply)); // tokenReward.mul(1e12).div(lpSupply)
        pool.lastRewardTime = block.timestamp;
    }

    // swap function
    function swapExactInputSingle(uint256 amountIn, IERC20 lpToken) public returns (uint256 amountOut) {

        lpToken.safeApprove(address(swapRouter), amountIn);

        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(lpToken),
                tokenOut: address(myToken),
                fee: poolFee,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        amountOut = swapRouter.exactInputSingle(params);
    }


    // Deposit LP tokens to MasterChef for 888 allocation.
    function deposit(uint256 _pid, uint256 _amount, uint _packageId, address _referrer) public nonReentrant { // address _referrer
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (_amount > 0 && address(T8ReferralContract) != address(0) && _referrer != msg.sender) {
            T8ReferralContract.recordReferral(msg.sender, _referrer, _packageId, _amount);
        }
        payOrLockupPendingLion(_pid);
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);

            if (pool.depositFeeBP > 0) {
                uint256 depositFee = _amount.mul(pool.depositFeeBP).div(10000);
                pool.lpToken.safeTransfer(feeAddress, depositFee);
                uint256 swapAmountIn = _amount.sub(depositFee).mul(4000).div(10000);
                swapExactInputSingle(swapAmountIn, pool.lpToken);
                user.amount = user.amount.add(_amount).sub(depositFee).sub(swapAmountIn);
            } else {
                uint256 swapAmountIn = _amount.mul(4000).div(10000);
                swapExactInputSingle(swapAmountIn, pool.lpToken);
                user.amount = user.amount.add(_amount).sub(swapAmountIn);
            }
        }
        user.rewardDebt = user.amount.mul(pool.accTokenPerShare).div(1e12); // .div(1e12)
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        payOrLockupPendingLion(_pid);
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }

        user.rewardDebt = user.amount.mul(pool.accTokenPerShare).div(1e12); // .div(1e12)
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    // function emergencyWithdraw(uint256 _pid) public nonReentrant {
    //     PoolInfo storage pool = poolInfo[_pid];
    //     UserInfo storage user = userInfo[_pid][msg.sender];
    //     uint256 amount = user.amount;
    //     user.amount = 0;
    //     user.rewardDebt = 0;
    //     user.rewardLockedUp = 0;
    //     user.nextHarvestUntil = 0;
    //     pool.lpToken.safeTransfer(address(msg.sender), amount);
    //     emit EmergencyWithdraw(msg.sender, _pid, amount);
    // }

    // Pay or lockup pending 888s.
    function payOrLockupPendingLion(uint256 _pid) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        if (user.nextHarvestUntil == 0) {
            user.nextHarvestUntil = block.timestamp.add(pool.harvestInterval);
        }

        uint256 pending = user.amount.mul(pool.accTokenPerShare).div(1e12).sub(user.rewardDebt); // .div(1e12).sub(user.rewardDebt)
        if (canHarvest(_pid, msg.sender)) {
            if (pending > 0 || user.rewardLockedUp > 0) {
                uint256 totalRewards = pending.add(user.rewardLockedUp);

                // reset lockup
                totalLockedUpRewards = totalLockedUpRewards.sub(user.rewardLockedUp);
                user.rewardLockedUp = 0;
                user.nextHarvestUntil = block.timestamp.add(pool.harvestInterval);

                // send rewards
                safeTokenTransfer(msg.sender, totalRewards);
                payReferralCommission(msg.sender, totalRewards);
            }
        } else if (pending > 0) {
            user.rewardLockedUp = user.rewardLockedUp.add(pending);
            totalLockedUpRewards = totalLockedUpRewards.add(pending);
            emit RewardLockedUp(msg.sender, _pid, pending);
        }
    }

    // Safe 888 transfer function, just in case if rounding error causes pool to not have enough 888.
    function safeTokenTransfer(address _to, uint256 _amount) internal {
        uint256 tokenBal = myToken.balanceOf(address(this));
        if (_amount > tokenBal) {
            myToken.transfer(_to, tokenBal);
        } else {
            myToken.transfer(_to, _amount);
        }
    }

    // Update dev address by the previous dev.
    function setDevAddress(address _devAddress) public {
        require(msg.sender == devAddress, "setDevAddress: FORBIDDEN");
        require(_devAddress != address(0), "setDevAddress: ZERO");
        devAddress = _devAddress;
    }

    function setFeeAddress(address _feeAddress) public {
        require(msg.sender == feeAddress, "setFeeAddress: FORBIDDEN");
        require(_feeAddress != address(0), "setFeeAddress: ZERO");
        feeAddress = _feeAddress;
    }

    // Pancake has to add hidden dummy pools in order to alter the emission, here we make it simple and transparent to all.
    function updateEmissionRate(uint256 _tokenPerSecond) public onlyOwner {
        massUpdatePools();
        emit EmissionRateUpdated(msg.sender, tokenPerSecond, _tokenPerSecond);
        tokenPerSecond = _tokenPerSecond;
    }

    // Update the lion referral contract address by the owner
    function setT8Referral(T8Referral _T8Referral) public onlyOwner {
        T8ReferralContract = _T8Referral;
    }

    // Update referral commission rate by the owner
    // function setReferralCommissionRate(uint16 _referralCommissionRate) public onlyOwner {
    //     require(_referralCommissionRate <= MAXIMUM_REFERRAL_COMMISSION_RATE, "setReferralCommissionRate: invalid referral commission rate basis points");
    //     referralCommissionRate = _referralCommissionRate;
    // }

    // Pay referral commission to the referrer who referred this user.
    function payReferralCommission(address _user, uint256 _pending) internal {
        if (address(T8ReferralContract) != address(0)) {
             T8Referral.Referral[] memory referrers = T8ReferralContract.getReferrer(_user);
             for(uint i=0; i < referrers.length; i++){
                 uint256 commissionAmount = _pending.mul(referrers[i].com_per).div(10000);
                 if (referrers[i].parent_address != address(0) && commissionAmount > 0) {
                    myToken.mint(referrers[i].parent_address, commissionAmount);
                    T8ReferralContract.recordReferralCommission(referrers[i].parent_address, commissionAmount);
                    emit ReferralCommissionPaid(_user, referrers[i].parent_address, commissionAmount);
                }
                 
             }
            
        }
    }
}