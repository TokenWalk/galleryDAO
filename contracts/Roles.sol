// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

contract Roles {
	struct Role {
		bool headOfHouse;
		bool member;
	}

    struct Member {
        Role roles;
        bool activeProposal;
    }

    mapping(address => Member) public _members;
    uint private _memberCount;
    address private _safe;

    modifier onlyMember {
        require(_members[msg.sender].roles.member == true, "not a member");
        _;
    }

    modifier onlyHeadOfHouse {
        require(_members[msg.sender].roles.headOfHouse == true, "not a head of house");
        _;
    }

    modifier onlySafe {
        require(msg.sender == _safe, "only gnosis safe may enter");
        _;
    }


    constructor(
        address[] memory heads_,
        address safe_
    ) {
        for(uint i=0; i<heads_.length; i++) {
            // create head of house member struct
            require(heads_[i] != address(0));
            _members[heads_[i]].roles.headOfHouse = true;
            _members[heads_[i]].roles.member = true;
            _memberCount++;
        }
        _safe = safe_;
    }

    function memberCount() public view virtual returns (uint) {
        return _memberCount;
    }

    // make this the easy multisig version, split out
    function headOfHouseEnterMember(address member) onlySafe external {
        //require(IERC20(_governanceToken).balanceOf(member) >= _minimumProposalAmount, "sponsor does not have enough gov tokens");
        _members[member].roles.member = true;
        _memberCount++;
    }

    function headOfHouseRemoveMember(address member) onlySafe external {
        //require(IERC20(_governanceToken).balanceOf(member) >= _minimumProposalAmount, "sponsor does not have enough gov tokens");
        _members[member].roles.member = false;
        _members[member].roles.headOfHouse = false;
        _memberCount--;
    }

}