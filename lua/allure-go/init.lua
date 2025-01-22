local M = {}
M.tag = "integration" -- Default build tag
M.test_path = "./..." -- Default test path

local test_job_ids = {}
local allure_job_ids = {}
local allure_results = "/allure-results"
local win
local is_stopped_running = false
local config_file_path = ".idea/allure.cfg"

local function ensure_directory_exists()
	local dir = ".idea"
	if vim.fn.isdirectory(dir) == 0 then
		vim.fn.mkdir(dir, "p") -- Create the directory
	end
end

local function load_config()
	ensure_directory_exists() -- Ensure the directory exists
	local project_root = vim.fn.getcwd()
	local full_path = project_root .. "/" .. config_file_path
	local file = io.open(full_path, "r")
	if file then
		for line in file:lines() do
			local key, value = line:match("(%S+)%s*=%s*(%S+)")
			if key == "tag" then
				M.tag = value
			elseif key == "test_path" then
				M.test_path = value
			end
		end
		file:close()
	else
		-- If the config file doesn't exist or is inaccessible, ensure a fallback value
		M.test_path = "test/tests"
	end
end

-- Call to load the configuration when the module is loaded
load_config()

local function save_config()
	ensure_directory_exists() -- Ensure the directory exists
	local project_root = vim.fn.getcwd()
	local full_path = project_root .. "/" .. config_file_path
	local file = io.open(full_path, "w")
	if file then
		file:write("tag = " .. M.tag .. "\n")
		file:write("test_path = " .. M.test_path .. "\n")
		file:close()
	end
end

local function stop_jobs(job_ids)
	if next(job_ids) ~= nil then
		for _, job_id in pairs(job_ids) do
			vim.fn.jobstop(job_id)
		end
		job_ids = {}
	end
end

local function notifyOnExitForTests(exit_code)
	if is_stopped_running then
		vim.api.nvim_win_close(win, true)
		vim.notify("⚠️  Tests running stopped!", vim.log.levels.INFO, { title = "Command Skipped" })
		is_stopped_running = false
		return
	end
	if exit_code == 0 then
		vim.api.nvim_win_close(win, true)
		vim.notify("✅ All tests passed!", vim.log.levels.INFO, { title = "Command Success" })
		return
	else
		M.check_and_run_allure()
		vim.notify("🚨 Tests failed!", vim.log.levels.ERROR, { title = "Command Failed" })
		return
	end
end

-- Run a command in a specified directory
local function run_command(command, cwd, on_exit, silent)
	local output = {}
	local job_id

	if silent then
		job_id = vim.fn.jobstart(command, {
			cwd = cwd,
			on_exit = function(_, exit_code)
				if on_exit then
					on_exit(exit_code)
				end
			end,
		})
	else
		-- Create a new buffer and window for output
		local buf = vim.api.nvim_create_buf(false, true)
		win = vim.api.nvim_open_win(buf, false, {
			split = "right",
			win = 0,
		})

		-- Write the command to the buffer as the first line
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Command: " .. command })

		job_id = vim.fn.jobstart(command, {
			cwd = cwd,
			on_stdout = function(_, data)
				if data then
					vim.api.nvim_buf_set_lines(buf, -1, -1, false, data)
					table.insert(output, table.concat(data, "\n"))
				end
			end,
			on_stderr = function(_, data)
				if data then
					vim.api.nvim_buf_set_lines(buf, -1, -1, false, data)
					table.insert(output, table.concat(data, "\n"))
				end
			end,
			on_exit = function(_, exit_code)
				if on_exit then
					on_exit(exit_code, win)
				end
			end,
		})
	end

	return job_id
end
-- Get allure path
function M.get_allure_root()
	local project_root = vim.fn.getcwd()
	local test_dir_path = project_root .. "/" .. M.test_path

	if vim.fn.isdirectory(project_root .. allure_results) == 1 then
		return project_root
	elseif vim.fn.isdirectory(test_dir_path .. allure_results) == 1 then
		return test_dir_path
	else
		local errMsg = string.format("Directory allure-results not found in %s of the project.", test_dir_path)
		vim.notify(errMsg, vim.log.levels.WARN, { title = "Directory Not Found" })
		return nil
	end
end

-- Clean allure results directory
function M.clean_allure_results_dir()
	local root_dir = M.get_allure_root()
	if root_dir then
		local full_path = root_dir .. allure_results
		os.execute(string.format("rm -rf %s/*", full_path))
	else
		vim.notify("allure-results directory does not exist.", vim.log.levels.WARN, { title = "Directory Not Found" })
	end
end

-- Check and run AllureServe
function M.check_and_run_allure()
	M.stop_allure()

	local allure_root = M.get_allure_root()
	if allure_root then
		local allure_job_id = run_command("allure serve ", allure_root, function(exit_code, output)
			if exit_code ~= 0 then
				local output_str = table.concat(output, "\n")
				vim.notify(
					"Allure serve failed with exit code " .. exit_code .. "\n" .. output_str,
					vim.log.levels.ERROR,
					{ title = "Allure Serve Failed" }
				)
			end
		end, true)
		table.insert(allure_job_ids, allure_job_id)
	else
		vim.notify(
			"Neither allure-results nor test/tests directory found in the project.",
			vim.log.levels.ERROR,
			{ title = "Directory Not Found" }
		)
	end
end

-- Stop the currently running command
function M.stop_allure()
	stop_jobs(allure_job_ids)
end

-- Run a specific Go test based on the cursor position
function M.run_go_test()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local row, col = cursor[1] - 1, cursor[2]
	local line = vim.api.nvim_get_current_line()

	local left_part = line:sub(1, col):match("[%w_]+$") or ""
	local right_part = line:sub(col + 1):match("^[%w_]+") or ""
	local word = left_part .. right_part

	M.clean_allure_results_dir()
	local command = string.format("go test ./%s -v -tags %s --allure-go.m %s", M.test_path, M.tag, word)

	local test_job_id = run_command(command, vim.fn.getcwd(), notifyOnExitForTests)
	table.insert(test_job_ids, test_job_id)
end

-- Run all Go tests
function M.run_go_test_all()
	M.clean_allure_results_dir()
	local command = string.format("go test ./%s -v -tags %s", M.test_path, M.tag)

	local test_job_id = run_command(command, vim.fn.getcwd(), notifyOnExitForTests)
	table.insert(test_job_ids, test_job_id)
end

-- Stop running tests
function M.stop_tests()
	is_stopped_running = true
	stop_jobs(test_job_ids)
end

-- Change the build tag used for Go tests and save the new configuration.
function M.change_tag()
	local new_tag = vim.fn.input("Enter new tag: ")
	if new_tag and #new_tag > 0 then
		M.tag = new_tag
		save_config() -- Save the updated tag
	end
end

-- Change the test path and save the new configuration
function M.set_test_path()
	local new_test_path = vim.fn.input("Enter new test path: ")
	if new_test_path and #new_test_path > 0 then
		M.test_path = new_test_path
		save_config() -- Save the updated tag
	end
end

function M.setup(opts)
	opts = opts or {}
	if opts.test_path then
		M.test_path = opts.test_path
	end
end

return M
