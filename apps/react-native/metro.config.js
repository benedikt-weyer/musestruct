const path = require('node:path');
const { getDefaultConfig, mergeConfig } = require('@react-native/metro-config');
const { withNativeWind } = require('nativewind/metro');

const projectRoot = __dirname;
const workspaceRoot = path.resolve(projectRoot, '../..');

/**
 * Metro configuration
 * https://reactnative.dev/docs/metro
 *
 * @type {import('@react-native/metro-config').MetroConfig}
 */
const config = {
	watchFolders: [workspaceRoot],
	resolver: {
		nodeModulesPaths: [
			path.resolve(projectRoot, 'node_modules'),
			path.resolve(workspaceRoot, 'node_modules'),
		],
	},
};

module.exports = withNativeWind(
	mergeConfig(getDefaultConfig(projectRoot), config),
	{ input: './global.css' },
);
