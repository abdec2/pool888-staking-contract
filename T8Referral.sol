// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract T8Referral is Ownable {
    using SafeERC20 for IERC20;

    struct Referral {
        address parent_address;
        uint8 level;
        uint com_per;
    }

    struct Packages {
        string name;
        uint cost;
        uint referral_levels;
        uint commission_level_1;
        uint commission_level_2;
        uint commission_level_3;
        uint commission_level_4;
    }

    mapping(address => bool) public operators;
    mapping(address => address) public referrers; // user address => referrer address
    mapping(address => Referral[]) public userReferral; // user address => referral struct
    mapping (uint => Packages) public packageById;
    mapping(address => uint) public userPackageId;

    mapping(address => uint256) public referralsCount; // referrer address => referrals count
    mapping(address => uint256) public totalReferralCommissions; // referrer address => total referral commissions

    event ReferralRecorded(address indexed user, address indexed referrer);
    event ReferralCommissionRecorded(address indexed referrer, uint256 commission);
    event OperatorUpdated(address indexed operator, bool indexed status);


    constructor() {
        packageById[1] = Packages("Freedom", 0, 0,0,0,0,0);
        packageById[2] = Packages("Bronze", 500*10**6, 1,200,0,0,0);
        packageById[3] = Packages("Silver", 1000*10**6, 2,300,200,0,0);
        packageById[4] = Packages("Gold", 3000*10**6, 3,500,200,100,0);
        packageById[5] = Packages("Platinum", 10000*10**6, 4,1000,500,200,100);
    }

    modifier onlyOperator {
        require(operators[msg.sender], "Operator: caller is not the operator");
        _;
    }

    function recordReferral(address _user, address _referrer, uint _packageId, uint _amount) public onlyOperator {
        require(_amount >= packageById[_packageId].cost, "Invalid Amount");
        if( userPackageId[_user] == 0 || userPackageId[_user] == 1 ) {
            // assign package to user 
            userPackageId[_user] = _packageId;
        }
        if ( _user != address(0) && _referrer != address(0) && _user != _referrer && referrers[_user] == address(0) ) {
            referrers[_user] = _referrer;
            referralsCount[_referrer] += 1;
            uint currnt_pkg_level = 0;
            address wallet_address = _user;

            for(uint8 level = 1; level <=4; level++) {
                address parent_address = referrers[wallet_address];
                if(parent_address != address(0)) {
                    if(packageById[userPackageId[parent_address]].referral_levels > currnt_pkg_level) {
                        uint comm_percent = 0;
                        if(level == 1) {
                            comm_percent = packageById[userPackageId[parent_address]].commission_level_1;
                        } 
                        if (level == 2) {
                            comm_percent = packageById[userPackageId[parent_address]].commission_level_2;
                        }
                        if (level == 3) {
                            comm_percent = packageById[userPackageId[parent_address]].commission_level_3;
                        }
                        if (level == 4) {
                            comm_percent = packageById[userPackageId[parent_address]].commission_level_4;
                        }
                        Referral memory user_referral = Referral(parent_address, level, comm_percent);
                        userReferral[_user].push(user_referral);
                    }
                } else {
                    break;
                }
                wallet_address = parent_address;
                currnt_pkg_level += 1;
            }

            emit ReferralRecorded(_user, _referrer);
        }
    }

    function recordReferralCommission(address _referrer, uint256 _commission) public onlyOperator {
        if (_referrer != address(0) && _commission > 0) {
            totalReferralCommissions[_referrer] += _commission;
            emit ReferralCommissionRecorded(_referrer, _commission);
        }
    }

    // Get the referrer address that referred the user
    function getReferrer(address _user) public view returns (Referral[] memory) {
        return userReferral[_user];
    }

    // Update the status of the operator
    function updateOperator(address _operator, bool _status) external onlyOwner {
        operators[_operator] = _status;
        emit OperatorUpdated(_operator, _status);
    }

    // Owner can drain tokens that are sent here by mistake
    function drainBEP20Token(IERC20 _token, uint256 _amount, address _to) external onlyOwner {
        _token.safeTransfer(_to, _amount);
    }
}