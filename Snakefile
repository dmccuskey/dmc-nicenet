# dmc-nicenet

try:
	if not gSTARTED: print( gSTARTED )
except:
	MODULE = "dmc-nicenet"
	include: "../DMC-Corona-Library/snakemake/Snakefile"

module_config = {
	"name": "dmc-nicenet",
	"module": {
		"dir": "dmc_corona",
		"files": [
			"dmc_nicenet.lua"
		],
		"requires": [
			"dmc-corona-boot",
			"DMC-Lua-Library",
			"dmc-objects"
		]
	},
	"examples": {
		"base_dir": "examples",
		"apps": [
			{
				"exp_dir": "dmc-nicenet-queue",
				"requires": [
					"dmc-mockserver"
				]
			}
		]
	},
	"tests": {
		"files": [],
		"requires": []
	}
}

register( "dmc-nicenet", module_config )
