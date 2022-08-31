// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Receiver.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

contract StakingContract is Ownable, ERC721Holder, ERC1155Receiver, ERC1155Holder {

    event Staked(
        address indexed user,
        address indexed nftAddress,
        uint256 tokenId,
        uint256 supply,
        uint256 indexed stakeId
    );

    event Withdraw(
        uint256 indexed stakeId,
        address indexed nftAddress,
        uint256 tokenId,
        uint256 supply,
        uint256 indexed reward
    );

    event PoolUpdated(
        uint256 indexed plan,
        uint256 indexed duration,
        uint256 indexed amount
    );

    IERC20Metadata rewardToken;

    enum AssetType {ERC1155, ERC721}
    enum poolType {SILVER, GOLD, VIP}

    struct PoolDetails{
        uint256 stakeDuration;
        uint256 rewardToken;
    }

    struct UserDetail {
        poolType plan;
        address user;
        AssetType nftType;
        address nftAddress;
        uint256 tokenId;
        uint256 supply;
        uint256 initialTime;
        uint256 endTime;
        bool status;
    }

    struct Sign {
        uint8 v;
        bytes32 r;
        bytes32 s;
        uint256 nonce;
    }

    mapping(poolType => PoolDetails) pools;
    mapping(uint256 => UserDetail) users;
    mapping(uint256 => bool) usedNonce;

    uint256 decimals;

    uint256 lastStakeId = 1;
    
    address public signer;

    constructor(IERC20Metadata token) {
        rewardToken = token;
        signer = msg.sender;
        decimals = token.decimals();
        pools[poolType.SILVER] = PoolDetails(30 days, 50 * 10 ** decimals);
        pools[poolType.GOLD] = PoolDetails(60 days, 120 * 10 ** decimals);
        pools[poolType.VIP] = PoolDetails(120 days, 260 * 10 ** decimals);
    }

    function getStakeDetails(uint256 stakeId) external view returns(UserDetail memory) {
        return users[stakeId];
    }

    function stake(address nftAddress, uint256 tokenId, uint256 supply, AssetType nftType, poolType plan, Sign memory sign) external returns(bool){
        require(!usedNonce[sign.nonce], "Invalid Nonce");
        usedNonce[sign.nonce] = true;
        verifySign(uint256(plan), msg.sender, sign);
        uint256 endTime = block.timestamp + pools[plan].stakeDuration;
        users[lastStakeId] = UserDetail(plan, msg.sender, nftType, nftAddress, tokenId, supply, block.timestamp, endTime, true);
        assetTransfer(msg.sender, address(this), nftType, nftAddress, tokenId, supply);
        emit Staked(msg.sender, nftAddress, tokenId, supply, lastStakeId);
        lastStakeId++;
        return true;
    }

    function unStake(uint256 stakeId, Sign memory sign) external returns(bool) {
        require(!usedNonce[sign.nonce], "Invalid Nonce");
        usedNonce[sign.nonce] = true;
        verifySign(stakeId, msg.sender, sign);
        require(users[stakeId].user == msg.sender, "Invalid User");
        require(users[stakeId].endTime <= block.timestamp, "Time not exceeds");
        assetTransfer(
            address(this),
            msg.sender,
            users[stakeId].nftType,
            users[stakeId].nftAddress,
            users[stakeId].tokenId,
            users[stakeId].supply
        );
        uint256 rewardAmount = users[stakeId].nftType == AssetType.ERC1155
                            ? users[stakeId].supply * pools[users[stakeId].plan].rewardToken
                            : pools[users[stakeId].plan].rewardToken;
        rewardToken.transferFrom(owner(), msg.sender, rewardAmount);
        emit Withdraw(stakeId, users[stakeId].nftAddress, users[stakeId].tokenId, users[stakeId].supply, rewardAmount);
        delete users[stakeId];
        return true;
    }

    function emergencyWithdraw(uint256 stakeId, Sign memory sign) external returns(bool) {
        require(!usedNonce[sign.nonce], "Invalid Nonce");
        usedNonce[sign.nonce] = true;
        verifySign(stakeId, msg.sender, sign);
        require(users[stakeId].user == msg.sender, "Invalid User");
        require(users[stakeId].endTime >= block.timestamp, "Time exceeds");

        assetTransfer(
            address(this),
            msg.sender,
            users[stakeId].nftType,
            users[stakeId].nftAddress,
            users[stakeId].tokenId,
            users[stakeId].supply
        );
        emit Withdraw(stakeId, users[stakeId].nftAddress, users[stakeId].tokenId, users[stakeId].supply, 0);
        delete users[stakeId];
        return true;
    }

    function setPoolDetails(uint256 plan, uint256 duration, uint256 amount) external onlyOwner returns(bool) {
        require(plan < 3, "Invaid Pool");
        pools[poolType(plan)] = PoolDetails(duration * 1 days, amount * 10 ** decimals); 
        emit PoolUpdated(plan, duration, amount);
        return true;
    }

    function verifySign(
        uint256 plan,
        address caller,
        Sign memory sign
    ) internal view {
        bytes32 hash = keccak256(
            abi.encodePacked(this, plan, caller, sign.nonce)
        );
        require(
            signer ==
                ecrecover(
                    keccak256(
                        abi.encodePacked(
                            "\x19Ethereum Signed Message:\n32",
                            hash
                        )
                    ),
                    sign.v,
                    sign.r,
                    sign.s
                ),
            "Owner sign verification failed"
        );
    }

    function assetTransfer(address from, address to, AssetType nftType, address nftAddress, uint256 tokenId, uint256 supply) internal returns(bool) {
        if(AssetType.ERC721 == nftType) {
            IERC721(nftAddress).safeTransferFrom(
                from,
                to,
                tokenId
            );
        }
        if(AssetType.ERC1155 == nftType) {
            IERC1155(nftAddress).safeTransferFrom(
                from,
                to,
                tokenId,
                supply,
                ""
            );
        }
        return true;
    }
}