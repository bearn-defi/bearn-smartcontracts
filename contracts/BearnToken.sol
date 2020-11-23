// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

// bearn.fi (BFI) with Governance Alpha
contract BFI is ERC20 {
    using SafeERC20 for IERC20;
    using SafeMath for uint;

    address public governance;
    mapping(address => bool) public minters;

    uint public cap = 210000 ether;

    // Initial emission plan:
    //
    // [1] Public fund: (57.5%)
    //   - Binance Smartchain Farming        7.5%
    //   - Binance Smartchain Vaults		20.0%
    //   - Binance Smartchain Staking Pool	25.0%
    //   - Ethereum Farming		             5.0%
    //
    // [2] Game fund: (5%)
    //   - Game Reserve                      5.0%
    //
    // [3] Community-governance fund: (20%)
    //   - Reserve                          10.0%
    //   - Treasury                         10.0%
    //
    // [4] Team fund: (17.5%)
    //   - Marketing                        10.0%
    //   - Dev                               7.5%
    address public publicFund;
    address public communityFund;
    address public teamFund;

    uint public publicFundPercent = 5750; // over 95
    uint public communityFundPercent = 2000; // over 95
    uint public teamFundPercent = 1750; // over 95

    uint public gameFundAmount = 10500 ether; // 210k * 5%

    uint public lastMinted;
    uint public constant mintingCooldownTime = 72 hours; // cant mint again less than 72 hours to avoid high aggressive emission

    event MintToFund(address indexed fund, uint amount);

    constructor () public ERC20("bearn.fi", "BFI") {
        governance = msg.sender;
        teamFund = msg.sender;

        // Pubic & community fund addresses set to deployer at start.
        // After setting up all the contracts deployer will forward funds to corresponding addresses.
        publicFund = msg.sender;
        communityFund = msg.sender;
    }

    modifier onlyGovernance() {
        require(msg.sender == governance, "!governance");
        _;
    }

    modifier checkMintedTime() {
        require(now >= lastMinted.add(mintingCooldownTime), "less than 72h");
        _;
    }

    function mint(address _to, uint _amount) public {
        require(msg.sender == governance || minters[msg.sender], "!governance && !minter");
        _mint(_to, _amount);
        _moveDelegates(address(0), _delegates[_to], _amount);
    }

    function burn(uint _amount) public {
        _burn(msg.sender, _amount);
        _moveDelegates(_delegates[msg.sender], address(0), _amount);
    }

    function burnFrom(address _account, uint _amount) public {
        uint decreasedAllowance = allowance(_account, msg.sender).sub(_amount, "ERC20: burn amount exceeds allowance");
        _approve(_account, msg.sender, decreasedAllowance);
        _burn(_account, _amount);
        _moveDelegates(_delegates[_account], address(0), _amount);
    }

    function transfer(address recipient, uint amount) public override returns (bool) {
        _moveDelegates(_delegates[_msgSender()], _delegates[recipient], amount);
        return super.transfer(recipient, amount);
    }

    function transferFrom(address sender, address recipient, uint amount) public override returns (bool) {
        _moveDelegates(_delegates[sender], _delegates[recipient], amount);
        return super.transferFrom(sender, recipient, amount);
    }

    function setGovernance(address _governance) external onlyGovernance {
        governance = _governance;
    }

    function addMinter(address _minter) external onlyGovernance {
        minters[_minter] = true;
    }

    function removeMinter(address _minter) external onlyGovernance {
        minters[_minter] = false;
    }

    function setCap(uint _cap) external onlyGovernance {
        require(_cap >= totalSupply(), "_cap is below current total supply");
        cap = _cap;
    }

    function setPublicFund(address _publicFund) external onlyGovernance {
        publicFund = _publicFund;
    }

    function setCommunityFund(address _communityFund) external onlyGovernance {
        communityFund = _communityFund;
    }

    function setTeamFund(address _teamFund) external onlyGovernance {
        teamFund = _teamFund;
    }

    function setSplitPercents(uint _publicFundPercent, uint _communityFundPercent, uint _teamFundPercent) external onlyGovernance {
        require(_publicFundPercent.add(_communityFundPercent).add(_teamFundPercent) == 9500, "!9500");
        publicFundPercent = _publicFundPercent;
        communityFundPercent = _communityFundPercent;
        teamFundPercent = _teamFundPercent;
    }

    function mintFunds(uint _amount) external onlyGovernance checkMintedTime {
        if (publicFundPercent > 0 && publicFund != address(0)) {
            uint _publicFundAmt = _amount.mul(publicFundPercent).div(9500);
            mint(publicFund, _publicFundAmt);
            emit MintToFund(publicFund, _publicFundAmt);
        }
        if (communityFundPercent > 0 && communityFund != address(0)) {
            uint _communityFundAmt = _amount.mul(communityFundPercent).div(9500);
            mint(communityFund, _communityFundAmt);
            emit MintToFund(communityFund, _communityFundAmt);
        }
        if (teamFundPercent > 0 && teamFund != address(0)) {
            uint _teamFundAmt = _amount.mul(teamFundPercent).div(9500);
            mint(teamFund, _teamFundAmt);
            emit MintToFund(teamFund, _teamFundAmt);
        }
        lastMinted = now;
    }

    // this could be called once!
    function mintToGameReserve(address _gameFund) external onlyGovernance {
        require(gameFundAmount > 0, "minted");
        require(_gameFund != address(0), "!_gameFund");
        mint(_gameFund, gameFundAmount);
        emit MintToFund(_gameFund, gameFundAmount);
        gameFundAmount = 0;
    }

    // This function allows governance to take unsupported tokens out of the contract.
    // This is in an effort to make someone whole, should they seriously mess up.
    // There is no guarantee governance will vote to return these.
    // It also allows for removal of airdropped tokens.
    function governanceRecoverUnsupported(IERC20 _token, address _to, uint _amount) external onlyGovernance {
        _token.safeTransfer(_to, _amount);
    }

    /**
     * @dev See {ERC20-_beforeTokenTransfer}.
     *
     * Requirements:
     *
     * - minted tokens must not cause the total supply to go over the cap.
     */
    function _beforeTokenTransfer(address from, address to, uint amount) internal virtual override {
        super._beforeTokenTransfer(from, to, amount);

        if (from == address(0)) {// When minting tokens
            require(totalSupply().add(amount) <= cap, "ERC20Capped: cap exceeded");
        }
    }

    // Copied and modified from YAM code:
    // https://github.com/yam-finance/yam-protocol/blob/master/contracts/token/YAMGovernanceStorage.sol
    // https://github.com/yam-finance/yam-protocol/blob/master/contracts/token/YAMGovernance.sol
    // Which is copied and modified from COMPOUND:
    // https://github.com/compound-finance/compound-protocol/blob/master/contracts/Governance/Comp.sol

    /// @dev A record of each accounts delegate
    mapping(address => address) internal _delegates;

    /// @notice A checkpoint for marking number of votes from a given block
    struct Checkpoint {
        uint32 fromBlock;
        uint votes;
    }

    /// @notice A record of votes checkpoints for each account, by index
    mapping(address => mapping(uint32 => Checkpoint)) public checkpoints;

    /// @notice The number of checkpoints for each account
    mapping(address => uint32) public numCheckpoints;

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint chainId,address verifyingContract)");

    /// @notice The EIP-712 typehash for the delegation struct used by the contract
    bytes32 public constant DELEGATION_TYPEHASH = keccak256("Delegation(address delegatee,uint nonce,uint expiry)");

    /// @dev A record of states for signing / validating signatures
    mapping(address => uint) public nonces;

    /// @notice An event thats emitted when an account changes its delegate
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);

    /// @notice An event thats emitted when a delegate account's vote balance changes
    event DelegateVotesChanged(address indexed delegate, uint previousBalance, uint newBalance);

    /**
     * @notice Delegate votes from `msg.sender` to `delegatee`
     * @param delegator The address to get delegatee for
     */
    function delegates(address delegator)
        external
        view
        returns (address)
    {
        return _delegates[delegator];
    }

    /**
     * @notice Delegate votes from `msg.sender` to `delegatee`
     * @param delegatee The address to delegate votes to
     */
    function delegate(address delegatee) external {
        return _delegate(msg.sender, delegatee);
    }

    /**
     * @notice Delegates votes from signatory to `delegatee`
     * @param delegatee The address to delegate votes to
     * @param nonce The contract state required to match the signature
     * @param expiry The time at which to expire the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function delegateBySig(
        address delegatee,
        uint nonce,
        uint expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external
    {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes(name())),
                getChainId(),
                address(this)
            )
        );

        bytes32 structHash = keccak256(
            abi.encode(
                DELEGATION_TYPEHASH,
                delegatee,
                nonce,
                expiry
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                structHash
            )
        );
        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), "YAX::delegateBySig: invalid signature");
        require(nonce == nonces[signatory]++, "YAX::delegateBySig: invalid nonce");
        require(now <= expiry, "YAX::delegateBySig: signature expired");
        return _delegate(signatory, delegatee);
    }

    /**
     * @notice Gets the current votes balance for `account`
     * @param account The address to get votes balance
     * @return The number of current votes for `account`
     */
    function getCurrentVotes(address account)
        external
        view
        returns (uint)
    {
        uint32 nCheckpoints = numCheckpoints[account];
        return nCheckpoints > 0 ? checkpoints[account][nCheckpoints - 1].votes : 0;
    }

    /**
     * @notice Determine the prior number of votes for an account as of a block number
     * @dev Block number must be a finalized block or else this function will revert to prevent misinformation.
     * @param account The address of the account to check
     * @param blockNumber The block number to get the vote balance at
     * @return The number of votes the account had as of the given block
     */
    function getPriorVotes(address account, uint blockNumber)
        external
        view
        returns (uint)
    {
        require(blockNumber < block.number, "YAX::getPriorVotes: not yet determined");

        uint32 nCheckpoints = numCheckpoints[account];
        if (nCheckpoints == 0) {
            return 0;
        }

        // First check most recent balance
        if (checkpoints[account][nCheckpoints - 1].fromBlock <= blockNumber) {
            return checkpoints[account][nCheckpoints - 1].votes;
        }

        // Next check implicit zero balance
        if (checkpoints[account][0].fromBlock > blockNumber) {
            return 0;
        }

        uint32 lower = 0;
        uint32 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint32 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            Checkpoint memory cp = checkpoints[account][center];
            if (cp.fromBlock == blockNumber) {
                return cp.votes;
            } else if (cp.fromBlock < blockNumber) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return checkpoints[account][lower].votes;
    }

    function _delegate(address delegator, address delegatee)
        internal
    {
        address currentDelegate = _delegates[delegator];
        uint delegatorBalance = balanceOf(delegator); // balance of underlying YAXs (not scaled);
        _delegates[delegator] = delegatee;

        emit DelegateChanged(delegator, currentDelegate, delegatee);

        _moveDelegates(currentDelegate, delegatee, delegatorBalance);
    }

    function _moveDelegates(address srcRep, address dstRep, uint amount) internal {
        if (srcRep != dstRep && amount > 0) {
            if (srcRep != address(0)) {
                // decrease old representative
                uint32 srcRepNum = numCheckpoints[srcRep];
                uint srcRepOld = srcRepNum > 0 ? checkpoints[srcRep][srcRepNum - 1].votes : 0;
                uint srcRepNew = srcRepOld.sub(amount);
                _writeCheckpoint(srcRep, srcRepNum, srcRepOld, srcRepNew);
            }

            if (dstRep != address(0)) {
                // increase new representative
                uint32 dstRepNum = numCheckpoints[dstRep];
                uint dstRepOld = dstRepNum > 0 ? checkpoints[dstRep][dstRepNum - 1].votes : 0;
                uint dstRepNew = dstRepOld.add(amount);
                _writeCheckpoint(dstRep, dstRepNum, dstRepOld, dstRepNew);
            }
        }
    }

    function _writeCheckpoint(
        address delegatee,
        uint32 nCheckpoints,
        uint oldVotes,
        uint newVotes
    )
        internal
    {
        uint32 blockNumber = safe32(block.number, "YAX::_writeCheckpoint: block number exceeds 32 bits");

        if (nCheckpoints > 0 && checkpoints[delegatee][nCheckpoints - 1].fromBlock == blockNumber) {
            checkpoints[delegatee][nCheckpoints - 1].votes = newVotes;
        } else {
            checkpoints[delegatee][nCheckpoints] = Checkpoint(blockNumber, newVotes);
            numCheckpoints[delegatee] = nCheckpoints + 1;
        }

        emit DelegateVotesChanged(delegatee, oldVotes, newVotes);
    }

    function safe32(uint n, string memory errorMessage) internal pure returns (uint32) {
        require(n < 2 ** 32, errorMessage);
        return uint32(n);
    }

    function getChainId() internal pure returns (uint) {
        uint chainId;
        assembly {chainId := chainid()}
        return chainId;
    }
}
