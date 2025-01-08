local M = {}
M.tag = 'integration' -- Default tag
local test_job_ids = {}
local allure_job_ids = {}
local allure_results = '/allure-results'
local win
local is_stopped_running = false

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
		vim.notify('⚠️  Tests running stopped!', 'info', { title = 'Command Skipped' })
		is_stopped_running = false
		return
	end
	if exit_code == 0 then
		vim.api.nvim_win_close(win, true)
		vim.notify('✅ All tests passed!', 'info', { title = 'Command Success' })
		return
	else
		M.check_and_run_allure()
		vim.notify('🚨 Tests failed!', 'error', { title = 'Command Failed' })
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
			split = 'right',
			win = 0,
		})

		job_id = vim.fn.jobstart(command, {
			cwd = cwd,
			on_stdout = function(_, data)
				if data then
					vim.api.nvim_buf_set_lines(buf, -1, -1, false, data)
					table.insert(output, table.concat(data, '\n'))
				end
			end,
			on_stderr = function(_, data)
				if data then
					vim.api.nvim_buf_set_lines(buf, -1, -1, false, data)
					table.insert(output, table.concat(data, '\n'))
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
	local test_dir_path = project_root .. '/test/tests'

	if vim.fn.isdirectory(project_root .. allure_results) == 1 then
		return project_root
	elseif vim.fn.isdirectory(test_dir_path .. allure_results) == 1 then
		return test_dir_path
	else
		vim.notify('Neither allure-results nor test/tests directory found in the project.', 'warn',
			{ title = 'Directory Not Found' })
		return nil
	end
end

-- Clean allure results directory
function M.clean_allure_results_dir()
	local root_dir = M.get_allure_root()
	if root_dir then
		local full_path = root_dir .. allure_results
		os.execute(string.format('rm -rf %s/*', full_path))
	else
		vim.notify('allure-results directory does not exist.', 'warn', { title = 'Directory Not Found' })
	end
end

-- Check and run AllureServe
function M.check_and_run_allure()
	M.stop_allure()

	local allure_root = M.get_allure_root()
	if allure_root then
		local allure_job_id = run_command('allure serve ', allure_root, function(exit_code, output)
			if exit_code ~= 0 then
				local output_str = table.concat(output, '\n')
				vim.notify('Allure serve failed with exit code ' .. exit_code .. '\n' .. output_str,
					'error', { title = 'Allure Serve Failed' })
			end
		end, true)
		table.insert(allure_job_ids, allure_job_id)
	else
		vim.notify('Neither allure-results nor test/tests directory found in the project.', 'warn',
			{ title = 'Directory Not Found' })
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

	local left_part = line:sub(1, col):match '[%w_]+$' or ''
	local right_part = line:sub(col + 1):match '^[%w_]+' or ''
	local word = left_part .. right_part

	M.clean_allure_results_dir()
	local command = string.format('go test ./test/tests -v -tags %s --allure-go.m %s', M.tag, word)

	local test_job_id = run_command(command, vim.fn.getcwd(), notifyOnExitForTests)
	table.insert(test_job_ids, test_job_id)
end

-- Run all Go tests
function M.run_go_test_all()
	M.clean_allure_results_dir()
	local command = string.format('go test ./test/tests -v -tags %s', M.tag)

	local test_job_id = run_command(command, vim.fn.getcwd(), notifyOnExitForTests)
	table.insert(test_job_ids, test_job_id)
end

-- Stop running tests
function M.stop_tests()
	is_stopped_running = true
	stop_jobs(test_job_ids)
end

-- Change the tag used for Go tests
function M.change_tag()
	local new_tag = vim.fn.input 'Enter new tag: '
	if new_tag and #new_tag > 0 then
		M.tag = new_tag
	end
end

function M.setup(opts)
	opts = opts or {}
	-- Define user commands for the plugin
	vim.api.nvim_create_user_command('AllureServe', M.check_and_run_allure, { desc = 'Run AllureServe' })
	vim.api.nvim_create_user_command('AllureStop', M.stop_allure, { desc = 'Stop AllureServe' })
	vim.api.nvim_create_user_command('TestFunc', M.run_go_test, { desc = 'Run test under cursor' })
	vim.api.nvim_create_user_command('TestAll', M.run_go_test_all, { desc = 'Run all tests' })
	vim.api.nvim_create_user_command('StopRunningTest', M.stop_tests, { desc = 'Stop running test' })
	vim.api.nvim_create_user_command('ChangeTag', M.change_tag, { desc = 'Change tag' })

	-- Map keybindings to trigger the functions
	vim.api.nvim_set_keymap('n', '<leader>tr', '<Cmd>AllureServe<CR>',
		{ noremap = true, silent = true, desc = '[r]un AllureServe' })
	vim.api.nvim_set_keymap('n', '<leader>ts', '<Cmd>AllureStop<CR>',
		{ noremap = true, silent = true, desc = '[s]top AllureServe' })
	vim.api.nvim_set_keymap('n', '<leader>tf', '<Cmd>TestFunc<CR>',
		{ noremap = true, silent = true, desc = 'Run test [f]unction under cursor' })
	vim.api.nvim_set_keymap('n', '<leader>ta', '<Cmd>TestAll<CR>',
		{ noremap = true, silent = true, desc = 'Run [a]ll tests' })
	vim.api.nvim_set_keymap('n', '<leader>tp', '<Cmd>StopRunningTest<CR>',
		{ noremap = true, silent = true, desc = 'Sto[p] currently running test' })
	vim.api.nvim_set_keymap('n', '<leader>tc', '<Cmd>ChangeTag<CR>',
		{ noremap = true, silent = true, desc = '[c]hange tag' })


	vim.keymap.set("n", "<Leader>h", function()
		if opts.name then
			print("hello, " .. opts.name)
		else
			print("hello")
		end
	end)
end

return M
