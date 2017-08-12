scriptencoding utf-8

let s:requred_modules = ['tornado', 'misaka', 'pygments']
let s:root_dir = expand('<sfile>:p:h:h')
let s:static_dir = s:root_dir . '/static'
let s:pyscript = s:root_dir . '/plugin/run.py'
let s:server_pid = 0
let s:initialized_preview = 0
let s:theme = ""

function! s:send_by_channel(msg) abort
  let handle = ch_open('localhost:' . g:livemark_vim_port, {'mode': 'json', 'waittime': 3000, 'timeout': 0})
  call ch_sendexpr(handle, a:msg)
  call ch_close(handle)
endfunction

function! s:initialize_pysocket() abort
  python <<EOF
import socket, vim, json
livemark_vim_port = int(vim.eval('g:livemark_vim_port'))
EOF
endfunction

function! s:send_by_pysocket(msg) abort
  python <<EOF
msg = vim.eval('a:msg')
msg['line'] = int(msg['line'])

msg = json.dumps([0, msg]).encode('utf-8')
sock = socket.create_connection(('localhost', livemark_vim_port))
sock.send(msg)
sock.close()
EOF
endfunction

function! s:send(msg) abort
  if has('channel') && !g:livemark_force_pysocket
    call s:send_by_channel(a:msg)
  else
    call s:send_by_pysocket(a:msg)
  endif
endfunction

function! livemark#move(cmd) abort
  echo 'LiveMark Browser Mode: ' . a:cmd
  let msg = {}
  let msg.line = line('w0')
  let msg.event = 'move'
  let msg.command = a:cmd
  call s:send(msg)
endfunction

noremap <Plug>LivemarkTop :call livemark#move('top')<CR>
noremap <Plug>LivemarkBottom :call livemark#move('bottom')<CR>
noremap <Plug>LivemarkUp :call livemark#move('up')<CR>
noremap <Plug>LivemarkDown :call livemark#move('down')<CR>
noremap <Plug>LivemarkPageUp :call livemark#move('page_up')<CR>
noremap <Plug>LivemarkPageDown :call livemark#move('page_down')<CR>
noremap <Plug>LivemarkHalfUp :call livemark#move('half_up')<CR>
noremap <Plug>LivemarkHalfDown :call livemark#move('half_down')<CR>

function! livemark#browser_mode() abort
  nmap <buffer> gg <Plug>LivemarkTop
  nmap <buffer> G  <Plug>LivemarkBottom
  nmap <buffer> k  <Plug>LivemarkUp
  nmap <buffer> j  <Plug>LivemarkDown
  nmap <buffer> <C-u> <Plug>LivemarkHalfUp
  nmap <buffer> <C-d> <Plug>LivemarkHalfDown
  nmap <buffer> <C-b> <Plug>LivemarkPageUp
  nmap <buffer> <C-f> <Plug>LivemarkPageDown
  nnoremap <buffer><nowait> <Esc> :call livemark#browser_mode_exit()<CR>
endfunction

function! livemark#browser_mode_exit() abort
  nunmap <buffer> gg
  nunmap <buffer> G
  nunmap <buffer> k
  nunmap <buffer> j
  nunmap <buffer> <C-u>
  nunmap <buffer> <C-d>
  nunmap <buffer> <C-b>
  nunmap <buffer> <C-f>
  nunmap <buffer> <Esc>
  echo 'LiveMark Browser Mode Exit'
endfunction

function! livemark#move_cursor() abort
  if !s:initialized_preview
    call livemark#update_preview()
    let s:initialized_preview = 1
    autocmd! livemark CursorMoved <buffer>
    return
  endif
endfunction

function! livemark#update_preview() abort
  let msg = {}
  let msg.text = getline(0, '$')
  if g:livemark_disable_scroll
    let msg.line = -1
  else
    let msg.line = line('w0')
  endif
  let msg.ext = &filetype
  let msg.event = 'update'
  call s:send(msg)
endfunction

function! s:check_pymodule(module) abort
  let cmd = system(g:livemark_python . ' -c "import ' . a:module . '"')
  if len(cmd) > 0
    return 1
  else
    return 0
  endif
endfunction

function! s:check_pymodules() abort
  let _error_modules = []
  for m in s:requred_modules
    let _err = s:check_pymodule(m)
    if _err
      echoerr 'Module ' . m . ' is not installed.'
      call add(_error_modules, m)
    endif
  endfor
  if len(_error_modules)
    return 1
  else
    return 0
  endif
endfunction

function! s:start_server() abort
  let l:options = ' --browser "' . g:livemark_browser . '"'
        \     . ' --port ' . g:livemark_browser_port
        \     . ' --vim-port ' . g:livemark_vim_port
        \     . ' --open-browser '

  if len(s:theme)
    let l:options .= ' --theme "' . s:theme . '"'
  elseif len(g:livemark_theme)
    let l:options .= ' --theme "' . g:livemark_theme . '"'
  endif

  if len(g:livemark_highlight_theme)
    let l:options .= ' --highlight-theme "' . g:livemark_highlight_theme . '"'
  endif

  let cmd = g:livemark_python . ' ' . s:pyscript . l:options
  let s:server_pid = system(cmd)
  if match(s:server_pid, '\D') >= 0
    call livemark#disable_livemark()
    echoerr 'Failed to start livemark server: ' . s:server_pid
  endif
endfunction

function! s:stop_server() abort
  if match(s:server_pid, '\D') < 0
    call system('kill ' . s:server_pid)
  endif
endfunction

function! s:check_features() abort
  if v:version < 704 || !has('patch1385') || !has('channel') 
    if !has('python')
      echoerr 'Livemark.vim requires vim which supports "channel" or "python".'
      return 1
    endif
  else
    if g:livemark_force_pysocket && !has('python')
      echoerr '"python" is selected to connect server, but this vim does support "python".'
            \ . ' Use "channel" instead.'
      let g:livemark_force_pysocket = 0
    endif
  endif
  return 0
endfunction

function! livemark#enable_livemark(...) abort
  if s:check_features() | return | endif
  if s:check_pymodules() | return | endif
  if len(a:000) > 0
    let s:theme = a:1
  endif

  if !has('channel') || g:livemark_force_pysocket
    call s:initialize_pysocket()
  endif
  augroup livemark
    autocmd!
    autocmd TextChanged,TextChangedI <buffer> call livemark#update_preview()
    autocmd CursorMoved <buffer> call livemark#move_cursor()
    autocmd VimLeave * call s:stop_server()
  augroup END
  call s:start_server()
  let s:theme = ""
endfunction

function! livemark#disable_livemark() abort
  augroup livemark
    autocmd!
  augroup END
  call s:stop_server()
endfunction

" vim set\ ts=2\ sts=2\ sw=2\ et
