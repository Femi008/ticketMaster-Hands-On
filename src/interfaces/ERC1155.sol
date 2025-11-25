// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IERC1155 {
    function safeTransferFrom(address from, address to, uint256 id, uint256 value, bytes calldata data) external;
    function safeBatchTransferFrom(address from, address to, uint256[] calldata ids, uint256[] calldata values, bytes calldata data) external;
    function balanceOf(address owner, uint256 id) external view returns (uint256);
    function balanceOfBatch(address[] calldata owners, uint256[] calldata ids) external view returns (uint256[] memory);
    function setApprovalForAll(address operator, bool approved) external;
    function isApprovedForAll(address owner, address operator) external view returns (bool);
}

interface IERC1155TokenReceiver {
    function onERC1155Received(address operator, address from, uint256 id, uint256 value, bytes calldata data) external returns (bytes4);
    function onERC1155BatchReceived(address operator, address from, uint256[] calldata ids, uint256[] calldata values, bytes calldata data) external returns (bytes4);
}

contract ERC1155 is IERC1155 {
    event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value);
    event TransferBatch(address indexed operator, address indexed from, address indexed to, uint256[] ids, uint256[] values);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    event URI(string value, uint256 indexed id);

    mapping(address => mapping(uint256 => uint256)) public balanceOf;
    mapping(address => mapping(address => bool)) public isApprovedForAll;

    // External ERC1155 functions
    function safeTransferFrom(address from, address to, uint256 id, uint256 value, bytes calldata data) external override {
        require(msg.sender == from || isApprovedForAll[from][msg.sender], "ERC1155: not approved");
        _safeTransferFrom(from, to, id, value, data);
    }

    function safeBatchTransferFrom(address from, address to, uint256[] calldata ids, uint256[] calldata values, bytes calldata data) external override {
        require(msg.sender == from || isApprovedForAll[from][msg.sender], "ERC1155: not approved");
        _safeBatchTransferFrom(from, to, ids, values, data);
    }

    function balanceOfBatch(address[] calldata owners, uint256[] calldata ids) external view override returns (uint256[] memory balances) {
        require(owners.length == ids.length, "ERC1155: owners/ids mismatch");
        balances = new uint256[](owners.length);
        unchecked {
            for (uint256 i = 0; i < owners.length; i++) {
                balances[i] = balanceOf[owners[i]][ids[i]];
            }
        }
    }

    function setApprovalForAll(address operator, bool approved) external override {
        isApprovedForAll[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    // Internal functions
    function _safeTransferFrom(address from, address to, uint256 id, uint256 value, bytes memory data) internal {
        require(to != address(0), "ERC1155: transfer to zero");
        balanceOf[from][id] -= value;
        balanceOf[to][id] += value;

        emit TransferSingle(msg.sender, from, to, id, value);

        if (to.code.length > 0) {
            require(
                IERC1155TokenReceiver(to).onERC1155Received(msg.sender, from, id, value, data) ==
                IERC1155TokenReceiver.onERC1155Received.selector,
                "ERC1155: unsafe transfer"
            );
        }
    }

    function _safeBatchTransferFrom(address from, address to, uint256[] memory ids, uint256[] memory values, bytes memory data) internal {
        require(to != address(0), "ERC1155: transfer to zero");
        require(ids.length == values.length, "ERC1155: ids/values mismatch");

        for (uint256 i = 0; i < ids.length; i++) {
            balanceOf[from][ids[i]] -= values[i];
            balanceOf[to][ids[i]] += values[i];
        }

        emit TransferBatch(msg.sender, from, to, ids, values);

        if (to.code.length > 0) {
            require(
                IERC1155TokenReceiver(to).onERC1155BatchReceived(msg.sender, from, ids, values, data) ==
                IERC1155TokenReceiver.onERC1155BatchReceived.selector,
                "ERC1155: unsafe batch transfer"
            );
        }
    }

    function _mint(address to, uint256 id, uint256 value, bytes memory data) internal {
        require(to != address(0), "ERC1155: mint to zero");
        balanceOf[to][id] += value;
        emit TransferSingle(msg.sender, address(0), to, id, value);

        if (to.code.length > 0) {
            require(
                IERC1155TokenReceiver(to).onERC1155Received(msg.sender, address(0), id, value, data) ==
                IERC1155TokenReceiver.onERC1155Received.selector,
                "ERC1155: unsafe mint"
            );
        }
    }

    function _batchMint(address to, uint256[] memory ids, uint256[] memory values, bytes memory data) internal {
        require(to != address(0), "ERC1155: mint to zero");
        require(ids.length == values.length, "ERC1155: ids/values mismatch");

        for (uint256 i = 0; i < ids.length; i++) {
            balanceOf[to][ids[i]] += values[i];
        }

        emit TransferBatch(msg.sender, address(0), to, ids, values);

        if (to.code.length > 0) {
            require(
                IERC1155TokenReceiver(to).onERC1155BatchReceived(msg.sender, address(0), ids, values, data) ==
                IERC1155TokenReceiver.onERC1155BatchReceived.selector,
                "ERC1155: unsafe batch mint"
            );
        }
    }

    function _burn(address from, uint256 id, uint256 value) internal {
        require(from != address(0), "ERC1155: burn from zero");
        balanceOf[from][id] -= value;
        emit TransferSingle(msg.sender, from, address(0), id, value);
    }

    function _batchBurn(address from, uint256[] memory ids, uint256[] memory values) internal {
        require(from != address(0), "ERC1155: burn from zero");
        require(ids.length == values.length, "ERC1155: ids/values mismatch");

        for (uint256 i = 0; i < ids.length; i++) {
            balanceOf[from][ids[i]] -= values[i];
        }

        emit TransferBatch(msg.sender, from, address(0), ids, values);
    }

    // Metadata
    function uri(uint256 id) public view virtual returns (string memory) {}

    // ERC165 support
    function supportsInterface(bytes4 interfaceId) public pure virtual returns (bool) {
        return interfaceId == 0x01ffc9a7 || interfaceId == 0xd9b67a26 || interfaceId == 0x0e89341c;
    }
}
