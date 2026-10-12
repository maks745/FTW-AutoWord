-- FTW AutoWord cloud key gate. Set the public service URL; NEVER put server secrets here.

local KEY_API = "https://xenox-keys.xenox-key-service.workers.dev"

local Http = game:GetService('HttpService')

local Players = game:GetService('Players')

local player = Players.LocalPlayer

local env = (type(getgenv) == 'function' and getgenv()) or _G

for _, name in ipairs({'FTW_AUTOWORD_KEY_STOP', 'XENO_KEY_STOP'}) do
    if type(env[name]) == 'function' then pcall(env[name]) end
end

for _, name in ipairs({'FTW40_STOP', 'FTW41_STOP'}) do

    if type(env[name]) == 'function' then pcall(env[name]) end

end



local function launchAutoWord()
-- FTW AutoWord V41 (X-prefix fast path + fallback recovery)

-- Client-side automation; game server decides whether any word is accepted.

-- No guarantee of victory. No remote/server manipulation.

local Players = game:GetService('Players')

local UIS = game:GetService('UserInputService')

local Tween = game:GetService('TweenService')

local player = Players.LocalPlayer

local pg = player:WaitForChild('PlayerGui')



-- Clean up any prior running instance, not just its visible window.

local env = (type(getgenv)=='function' and getgenv()) or _G

for _,key in ipairs({'FTW40_STOP','FTW41_STOP'}) do

    pcall(function() if type(env[key])=='function' then env[key]() end end)

end

for _,g in ipairs(pg:GetChildren()) do

    if g:IsA('ScreenGui') and (g.Name:match('^FTW_V%d+$') or g.Name:match('^FTW_V%d+_ERROR$')) then g:Destroy() end

end



local A = {alive=true, enabled=true, hint=false, mode='AUTO', input='auto', speed=.075, retrySpeed=.020, fastRetry=false,

   tries=0, maxAttempts=5, attemptsThisTurn=0, status='Initializing', stage='WAITING', prefix='', current='', method='',

   used={}, bad={}, good={}, rival={}, seen={}, log={}, draft='', draftAt=0,

   round=0, tracked='', turnID=0, lastSend=0, inputLock=false, lastInput='',

   newTurnAt=0, opponentCandidate='', opponentTurn=false, opponentStartPrefix='',

   awaitingResult=nil, missingSince=nil, screen=nil, display=nil, lastSearch=0,

   connections={}, jobs={}, failures=0, confirmed=0, resetBetweenMatches=false, failedThisTurn={}, failedPrefix='', resultWait=.32}

local CFG={USED='ftw_used_words_v37.txt',GOOD='ftw_word_history_v7.txt',COMMON='ftw_common_v5.txt',BIG='ftw_large_v5.txt'}

local function safe(f,...) local ok,r=pcall(f,...); if ok then return r end; warn('[FTW AutoWord]',r); return nil end

local function setStatus(s) A.status=tostring(s) end

local function stop()

    if not A.alive then return end

    A.alive=false; A.enabled=false; A.turnID=A.turnID+1

    for _,c in ipairs(A.connections) do safe(function() c:Disconnect() end) end

    if A.gui then A.gui:Destroy() end

end

env.FTW41_STOP=stop



local function valid(w) return type(w)=='string' and #w>=4 and #w<=30 and w:match('^[a-z]+$')~=nil end

local function readLines(file)

    if type(readfile)~='function' or type(isfile)~='function' then return nil end

    local ok,exists=pcall(isfile,file); if not ok or not exists then return nil end

    local success,data=pcall(readfile,file); return success and type(data)=='string' and data or nil

end

local function writeLines(file,data)

    if type(writefile)=='function' then safe(writefile,file,data) end

end

local function record(w,kind)

    if not valid(w) then return end

    if kind=='RIVAL' then

        if A.rival[w] then return end

        A.rival[w]=true

    elseif kind=='YOU' then

        if A.seen[w] then return end

    end

    A.seen[w]=true

    A.log[#A.log+1]={word=w,who=kind}

    if #A.log>250 then table.remove(A.log,1) end

end

local function remember(w)

    if not valid(w) or A.used[w] then return end

    A.used[w]=true

    A.usedDirty=true

end

local function saveUsed()

    local t={}; for w in pairs(A.used) do t[#t+1]=w end

    table.sort(t); writeLines(CFG.USED,table.concat(t,'\n')); A.usedDirty=false

end

local function saveKnowledge()

    local t={};for w in pairs(A.good) do t[#t+1]='G '..w end

    for w in pairs(A.bad) do t[#t+1]='R '..w end

    table.sort(t);writeLines(CFG.GOOD,table.concat(t,'\n'));A.knowledgeDirty=false

end

for w in (readLines(CFG.USED) or ''):gmatch('[a-z]+') do if valid(w) then A.used[w]=true end end

for line in (readLines(CFG.GOOD) or ''):gmatch('[^\r\n]+') do

    local k,w=line:match('^([GR])%s+([a-z]+)$')

    if w and valid(w) then if k=='G' then A.good[w]=true else A.bad[w]=true end end

end



-- Dictionary index, built once and read without scanning 370k words on every turn.

local fallback=[[about above after again always answer apple banana beautiful before better book brother business camera change children choose computer country create danger different direction elephant energy enough entertainment error estate evening example family father finish flower forest friend future garden general ghost golden green happy history house important island january japanese knowledge language letter light locations literature mother mountain natural necessary november number ocean only orange outside people professional questions quick rabbit remember requirements responsibility school search september something statistics technology technologies there through tonight together tomorrow understanding university useful vacation violet winter woman yellow yesterday young yourself youth zebra]]

local extras=[[xenon xylophone xenophobia xylem xenolith zealous zenith zephyr zoology zebra quasar quartz quarantine quicksilver quarry yonder yearling yellowish nyssa nyalas nyala nyctophobia nyctophile nyctinasty xerography xiphoid zydeco]]

-- Small instant-response lexicon for difficult X prefixes. It is a candidate list,

-- not proof that the Roblox server accepts every entry.

local X_FAST=[[xray xrayfish xenon xenia xylem xylitol xylophone xerox xeric xerophyte

xerography xeroderma xenial xenolith xenograft xenophobia xenophobic xenophile

xenogenesis xenobiology xenobiotic xiphoid xiphosuran xanthic xanthate xanthan

xanthophyll xanthine xanthoma xanthous xylocarp xylotomy xylophonist]]

local D={byPrefix={},set={},ready=false,loaded=0,source='offline'}

local function add(w,rank)

    w=w:lower()

    if not valid(w) then return end

    if D.set[w] then

        if rank < D.set[w] then D.set[w]=rank end

        return

    end

    D.set[w]=rank

    for i=1,math.min(#w,12) do

        local p=w:sub(1,i)

        local arr=D.byPrefix[p]

        if not arr then arr={};D.byPrefix[p]=arr end

        arr[#arr+1]=w

    end

    D.loaded=D.loaded+1

end

-- Prefer everyday words. Specialized vocabulary is kept only as a last resort.
for w in fallback:gmatch('[a-z]+') do add(w,180) end
for w in extras:gmatch('[a-z]+') do add(w,25000) end
for w in X_FAST:gmatch('[a-z]+') do add(w,20000) end

D.ready=true

local function choose(prefix,ends,startsWith)
    local arr=D.byPrefix[prefix] or {}
    local best, bestScore
    local function candidate(w, tier)
        if A.used[w] or A.bad[w] or A.rival[w] or A.failedThisTurn[w] then return end
        if ends~='' and w:sub(-#ends)~=ends then return end
        if startsWith and w:sub(1,#startsWith)~=startsWith then return end
        local rank=D.set[w] or 30000
        -- Tier 1: common words; tier 2: less common; tier 3: rare backup.
        if (tier==1 and rank>4000) or (tier==2 and rank>10000) then return end
        -- Known accepted words take precedence within the same vocabulary tier.
        local score=(A.good[w] and -1000000 or 0)+#w*95+rank*.75
        if not bestScore or score<bestScore then best,bestScore=w,score end
    end
    -- Prefer familiar words, even if a rare dictionary entry is shorter.
    for tier=1,3 do
        best,bestScore=nil,nil
        for _,w in ipairs(arr) do candidate(w,tier) end
        if best then return best end
    end
    return nil
end

local URLS={

    [CFG.COMMON]='https://raw.githubusercontent.com/first20hours/google-10000-english/master/google-10000-english.txt',

    [CFG.BIG]='https://raw.githubusercontent.com/dwyl/english-words/master/words_alpha.txt'

}

local function getDictionaryText(file)

    local cached=readLines(file)

    if cached and #cached>10000 then return cached end

    local url=URLS[file]

    if not url then return nil end

    local ok,raw=pcall(function()return game:HttpGet(url)end)

    if ok and type(raw)=='string' and #raw>10000 then

        writeLines(file,raw)

        return raw

    end

    return cached

end

local function loadDictionary(file,priority)

    local raw=getDictionaryText(file)

    if not raw then return end

    local n,kept=0,0

    for w in raw:gmatch('[^\r\n]+') do

        if not A.alive then return end

        n=n+1

        if priority==1 and n>10000 then break end

        -- Sample the large alphabetical dictionary throughout its full range.

        -- Index at most about 60k entries to avoid multi-million GUI allocations.

        if priority==1 or n%6==0 then

            add(w:lower(),priority==1 and n or 30000)

            kept=kept+1

        end

        if n%4000==0 then task.wait() end

    end

end

task.spawn(function()

    loadDictionary(CFG.COMMON,1)

    loadDictionary(CFG.BIG,2)

    A.dictReady=true

end)



local function elem(parent,kind,p)

    local o=Instance.new(kind)

    for k,v in pairs(p or {}) do o[k]=v end

    o.Parent=parent

    return o

end

local function round(gui,rad)

    elem(gui,'UICorner',{CornerRadius=UDim.new(0,rad or 9)})

end

local C={bg=Color3.fromRGB(11,17,30),card=Color3.fromRGB(23,32,51),border=Color3.fromRGB(48,65,96),txt=Color3.fromRGB(232,242,255),dim=Color3.fromRGB(145,162,190),a=Color3.fromRGB(78,135,255),yes=Color3.fromRGB(53,212,165),no=Color3.fromRGB(250,117,128)}

local function label(parent,text,pos,size,fontSize,bold)

    return elem(parent,'TextLabel',{BackgroundTransparency=1,Text=text,Position=pos,Size=size,Font=bold and Enum.Font.GothamBold or Enum.Font.Gotham,TextSize=fontSize or 13,TextColor3=C.txt,TextXAlignment=Enum.TextXAlignment.Left,TextTruncate=Enum.TextTruncate.AtEnd})

end

local function btn(parent,text,pos,size,color,fn)

    local b=elem(parent,'TextButton',{Position=pos,Size=size,Text=text,Font=Enum.Font.GothamBold,TextSize=12,TextColor3=C.txt,BackgroundColor3=color or C.card,BorderSizePixel=0,AutoButtonColor=true})

    round(b,8); table.insert(A.connections,b.MouseButton1Click:Connect(fn));return b

end

local gui=elem(pg,'ScreenGui',{Name='FTW_V41',ResetOnSpawn=false,DisplayOrder=120,IgnoreGuiInset=false});A.gui=gui

local frame=elem(gui,'Frame',{BackgroundColor3=C.bg,Size=UDim2.fromOffset(400,568),Position=UDim2.fromOffset(28,60),BorderSizePixel=0})

round(frame,15);elem(frame,'UIStroke',{Color=C.border,Thickness=1})

local hdr=elem(frame,'Frame',{BackgroundTransparency=1,Size=UDim2.new(1,0,0,51),Active=true})

label(hdr,'FTW AutoWord',UDim2.fromOffset(16,11),UDim2.fromOffset(220,26),16,true)

label(hdr,'V40',UDim2.fromOffset(245,15),UDim2.fromOffset(45,20),11,true).TextColor3=C.yes

local area=elem(frame,'Frame',{BackgroundTransparency=1,Position=UDim2.fromOffset(14,57),Size=UDim2.new(1,-28,1,-70)})

local stage=label(area,'WAITING',UDim2.fromOffset(6,3),UDim2.new(1,-12,0,18),12,true);stage.TextColor3=C.yes

local prefixText=label(area,'---',UDim2.fromOffset(6,24),UDim2.new(1,-12,0,42),30,true)

local wordText=label(area,'Suggested: ---',UDim2.fromOffset(6,76),UDim2.new(1,-12,0,24),17,true)

local statusText=label(area,'Initializing',UDim2.fromOffset(6,107),UDim2.new(1,-12,0,42),12,false)

statusText.TextWrapped=true;statusText.TextTruncate=Enum.TextTruncate.None

local meta=label(area,'Words: 0 | Used: 0 | Rival: 0',UDim2.fromOffset(6,157),UDim2.new(1,-12,0,22),12)

local stats=label(area,'Input: AUTO | Dictionary: offline',UDim2.fromOffset(6,180),UDim2.new(1,-12,0,22),11)

local switch=btn(area,'AUTO: ON',UDim2.fromOffset(6,220),UDim2.fromOffset(174,34),C.a,function() A.enabled=not A.enabled; A.turnID=A.turnID+1;setStatus(A.enabled and 'Auto enabled' or 'Auto paused') end)

btn(area,'HINT / AUTO',UDim2.fromOffset(191,220),UDim2.fromOffset(174,34),C.card,function() A.hint=not A.hint;A.turnID=A.turnID+1;setStatus(A.hint and 'Hint-only mode' or 'Auto-input mode') end)

btn(area,'RETRY TURN',UDim2.fromOffset(6,263),UDim2.fromOffset(174,33),C.card,function() if A.attemptsThisTurn>=A.maxAttempts then setStatus('5 attempts exhausted; wait for next turn');return end;A.turnID=A.turnID+1;A.lastSentTurn=-1;setStatus('Rearmed current turn') end)

btn(area,'RESET USED',UDim2.fromOffset(191,263),UDim2.fromOffset(174,33),C.card,function() A.used={};A.seen={};A.rival={};A.usedDirty=true;saveUsed();setStatus('Used-word list cleared manually') end)

btn(area,'COPY LOG',UDim2.fromOffset(6,307),UDim2.fromOffset(174,33),C.card,function()

    local lines={};for _,x in ipairs(A.log) do lines[#lines+1]=x.who..': '..x.word end

    if type(setclipboard)=='function' then safe(setclipboard,table.concat(lines,'\n'));setStatus('Copied log') end

end)

btn(area,'COPY DIAG',UDim2.fromOffset(191,307),UDim2.fromOffset(174,33),C.card,function()

    local s=string.format('FTW AutoWord | stage=%s | prefix=%s | ourTurn=%s | input=%s | draft=%s | method=%s | words=%d | sent=%d | rival=%d | errors=%d | attempts=%d/%d',A.stage,A.prefix,tostring(A.ourTurn),A.lastInput,A.draft,A.method,D.loaded,A.submitted or 0,A.rivalCount or 0,A.failures,A.attemptsThisTurn,A.maxAttempts)

    if type(setclipboard)=='function' then safe(setclipboard,s);setStatus('Copied diagnostic') end

end)

local logText=label(area,'Last accepted: ---',UDim2.fromOffset(6,359),UDim2.new(1,-12,0,20),11)



btn(hdr,'×',UDim2.new(1,-39,0,10),UDim2.fromOffset(27,27),C.no,stop)

local minimized=false

btn(hdr,'–',UDim2.new(1,-74,0,10),UDim2.fromOffset(27,27),C.card,function()

    minimized=not minimized;area.Visible=not minimized;frame.Size=UDim2.fromOffset(400,minimized and 51 or 568)

end)

local dragging,start,initial=false,nil,nil

table.insert(A.connections,hdr.InputBegan:Connect(function(i)

    if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then

        dragging=true;start=i.Position;initial=frame.Position

        table.insert(A.connections,i.Changed:Connect(function() if i.UserInputState==Enum.UserInputState.End then dragging=false end end))

    end

end))

table.insert(A.connections,UIS.InputChanged:Connect(function(i)

    if dragging and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then

        local delta=i.Position-start;frame.Position=UDim2.new(initial.X.Scale,initial.X.Offset+delta.X,initial.Y.Scale,initial.Y.Offset+delta.Y)

    end

end))

table.insert(A.connections,UIS.InputBegan:Connect(function(i,consumed)

    if not consumed and i.KeyCode==Enum.KeyCode.RightShift then A.enabled=not A.enabled;A.turnID=A.turnID+1 end

end))



local function findScreen()

    local s=A.screen

    if s and s.Parent==pg and s:FindFirstChild('QuestionLabel',true) and s:FindFirstChild('AnswerInput',true) then return s end

    for _,g in ipairs(pg:GetChildren()) do

        if g:IsA('ScreenGui') and g~=gui and g:FindFirstChild('QuestionLabel',true) and g:FindFirstChild('AnswerInput',true) then A.screen=g;return g end

    end

    A.screen=nil;return nil

end

local function readKeys(container)

    local keys=container and container:FindFirstChild('Keys',true)

    if not keys then return '' end

    local arr={}

    for _,o in ipairs(keys:GetChildren()) do

        local n=tonumber(o.Name)

        if n then

            local t=o:FindFirstChildWhichIsA('TextLabel',true)

            if t and t.Text:match('^[A-Za-z]$') then arr[#arr+1]={n=n,t=t.Text:lower()} end

        end

    end

    table.sort(arr,function(a,b)return a.n<b.n end)

    local r={};for _,e in ipairs(arr) do r[#r+1]=e.t end

    return table.concat(r)

end

local function nearestDisplay()

    if A.display and A.display:IsDescendantOf(workspace) then return A.display end

    local root=workspace:FindFirstChild('Meta') or workspace

    local pos=player.Character and player.Character:FindFirstChild('HumanoidRootPart')

    local best,dist

    for _,o in ipairs(root:GetDescendants()) do

        if o.Name=='MatchDisplay' then

            local model=o:FindFirstAncestorWhichIsA('Model')

            local ok,p=pcall(function() return model:GetPivot().Position end)

            local d=pos and ok and (p-pos.Position).Magnitude or 0

            if not dist or d<dist then best=o;dist=d end

        end

    end

    A.display=best;return best

end

local function parseCategory(t)

    if type(t)~='string' then return nil,'' end

    local s=t:lower():gsub('%s+','')

    if #s<=12 and s:match('^[a-z]+$') then return s,'' end

    local first,last=t:lower():match('^%s*([a-z]+)[^a-z]+([a-z]+)%s*$')

    if first and last and #first<=12 and #last<=12 then return first,last end

    return nil,''

end

local function screenshotState()

    local s=findScreen();local d=nearestDisplay()

    local q=s and s:FindFirstChild('QuestionLabel',true)

    local answer=s and s:FindFirstChild('AnswerInput',true)

    local raw=d and d:FindFirstChild('Category',true)

    local prefix,suffix=parseCategory(raw and raw.Text or '')

    local question=q and q.Text:lower() or ''

    local active=s and answer and answer.Visible and q and q.Visible and (question:find('type a word',1,true)~=nil or question:find('your turn',1,true)~=nil)

    local gameOver=pg:FindFirstChild('rankedMatchOver')

    local ended=gameOver and gameOver:IsA('ScreenGui') and gameOver.Enabled

    return {prefix=prefix,suffix=suffix,ours=(active and not ended) or false,

        input=readKeys(answer),opponent=readKeys(d and d:FindFirstChild('AnswerInput',true)),

        question=question,ended=ended,category=raw and raw.Text or ''}

end

local function getTimeLeft()

    local s=findScreen()

    local bottom=s and s:FindFirstChild('BottomBar',true)

    local center=bottom and bottom:FindFirstChild('CenterBar')

    local clock=center and center:FindFirstChild('Timer')

    local text=clock and clock:FindFirstChild('Timer',true)

    if text and text:IsA('TextLabel') then return tonumber(text.Text) end

    return nil

end



local function sendKey(key)

    local vi=A.vi

    if vi==nil then vi=safe(function()return game:GetService('VirtualInputManager') end); A.vi=vi or false end

    if vi==false then vi=nil end

    local method=A.input

    if method=='auto' then method=vi and 'vim' or 'keypress' end

    A.method=method

    if method=='vim' and vi then

        local ok=pcall(function()vi:SendKeyEvent(true,key,false,game);task.wait(.012);vi:SendKeyEvent(false,key,false,game)end)

        return ok

    end

    if type(keypress)=='function' and type(keyrelease)=='function' then

        local code=key.Value;if code>=97 and code<=122 then code=code-32 end

        return pcall(function()keypress(code);task.wait(.015);keyrelease(code)end)

    end

    return false

end

local function isCurrent(id,prefix)

    if not A.alive or not A.enabled or A.hint or id~=A.turnID then return false end

    local x=screenshotState()

    return x.ours and x.prefix==prefix and not x.ended

end

-- The game uses individual letter tiles, not an ordinary TextBox.

-- Avoid Ctrl+A (unsupported); rapidly delete only the visible letters.

local function clearInput(prefix,id)

    local observed=screenshotState().input

    local limit=math.max(#observed+3,5)

    for n=1,limit do

        if not isCurrent(id,prefix) then return 'cancelled' end

        local current=screenshotState().input

        if current=='' then return 'ok' end

        if not sendKey(Enum.KeyCode.Backspace) then return 'key_error' end

        task.wait(.012)

    end

    return screenshotState().input=='' and 'ok' or 'backspace_stuck'

end

local function typeAnswer(word,prefix,id)

    if A.attemptsThisTurn >= A.maxAttempts then return 'limit_reached' end

    local x=screenshotState();local current=x.input

    -- Reuse an already completed word only if it has not been tried/rejected.

    if valid(current) and current:sub(1,#prefix)==prefix

       and not A.bad[current] and not A.used[current] and not A.failedThisTurn[current] then

       word=current

    end

    if current~='' and word:sub(1,#current)~=current then

        local result=clearInput(prefix,id)

        if result~='ok' then return result end

        current=''

    end

    if not isCurrent(id,prefix) then return 'cancelled' end

    for i=#current+1,#word do

        if not isCurrent(id,prefix) then return 'cancelled' end

        local key=Enum.KeyCode[word:sub(i,i):upper()]

        if not key or not sendKey(key) then return 'key_error' end

        task.wait(A.fastRetry and A.retrySpeed or A.speed)

    end

    local verify=screenshotState()

    if verify.input~=word then return 'mismatch:'..verify.input end

    if not isCurrent(id,prefix) then return 'cancelled' end

    if A.attemptsThisTurn >= A.maxAttempts then return 'limit_reached' end

    if not sendKey(Enum.KeyCode.Return) then return 'enter_error' end

    A.attemptsThisTurn=A.attemptsThisTurn+1

    remember(word);record(word,'YOU');A.submitted=(A.submitted or 0)+1

    A.awaitingResult={word=word,at=os.clock(),prefix=prefix,id=id}

    return 'submitted:'..word

end



local function updateOpponent(x,previous)

    -- A typed draft is NOT a confirmed word. The server UI may also show text

    -- only after acceptance: keep those cases as unconfirmed rather than guessing.

    if not x.ours and not x.ended then

        if not A.opponentTurn then A.pendingRival=nil end

        local typed=x.opponent~='' and x.opponent or x.input

        if typed~='' and typed~=A.draft then A.draft=typed;A.draftAt=os.clock() end

        A.opponentTurn=true

    elseif x.ours and A.opponentTurn then

        -- Moving to the next turn alone is not proof of server acceptance.

        -- Keep draft out of RIVAL/GOOD/USED until explicit player confirmation.

        if valid(A.draft) then

            A.pendingRival=A.draft

            setStatus('Opponent word unverified: '..A.draft)

        end

        A.draft='';A.opponentTurn=false

    elseif x.ended then A.draft='';A.opponentTurn=false end

end



-- Manual confirmation avoids the previous false-positive "typed = accepted" bug.

btn(area,'CONFIRM RIVAL',UDim2.fromOffset(6,348),UDim2.fromOffset(174,29),C.card,function()

    if A.pendingRival and valid(A.pendingRival) then

        local w=A.pendingRival;record(w,'RIVAL');remember(w);A.rivalCount=(A.rivalCount or 0)+1

        logText.Text='Rival accepted: '..w;A.pendingRival=nil

    else setStatus('No unverified rival word') end

end)

btn(area,'REJECT RIVAL',UDim2.fromOffset(191,348),UDim2.fromOffset(174,29),C.card,function()

    A.pendingRival=nil;setStatus('Opponent draft discarded')

end)

logText.Position=UDim2.fromOffset(6,386)



-- Separate controls: comfortable normal speed; rapid correction after a failed submission.

local speedNormalLabel=label(area,'Normal typing: 75 ms/letter',UDim2.fromOffset(6,414),UDim2.fromOffset(260,24),12,true)

local speedRetryLabel=label(area,'Retry typing: 20 ms/letter',UDim2.fromOffset(6,453),UDim2.fromOffset(260,24),12,true)

local function speedDisplay()

    speedNormalLabel.Text=string.format('Normal typing: %d ms/letter',math.floor(A.speed*1000+.5))

    speedRetryLabel.Text=string.format('Retry typing: %d ms/letter',math.floor(A.retrySpeed*1000+.5))

end

btn(area,'−',UDim2.fromOffset(274,410),UDim2.fromOffset(42,30),C.card,function()

    A.speed=math.max(.030,A.speed-.010);speedDisplay()

end)

btn(area,'+',UDim2.fromOffset(323,410),UDim2.fromOffset(42,30),C.card,function()

    A.speed=math.min(.160,A.speed+.010);speedDisplay()

end)

btn(area,'−',UDim2.fromOffset(274,449),UDim2.fromOffset(42,30),C.card,function()

    A.retrySpeed=math.max(.010,A.retrySpeed-.005);speedDisplay()

end)

btn(area,'+',UDim2.fromOffset(323,449),UDim2.fromOffset(42,30),C.card,function()

    A.retrySpeed=math.min(.055,A.retrySpeed+.005);speedDisplay()

end)

speedDisplay()



local function loop()

    local previous=nil

    local lastSave=os.clock();local lastRefresh=0;local lastSeenPrefix=''

    while A.alive and gui.Parent do

        local x=screenshotState()

        A.lastInput=x.input; A.ourTurn=x.ours

        updateOpponent(x,previous)

        local usable=x.ours and x.prefix and x.prefix~=''

        if x.ended then

            A.stage='MATCH OVER';A.turnID=A.turnID+1;A.lastSentTurn=nil

        elseif usable then

            A.stage='YOUR TURN'

            if not previous or not previous.ours or previous.prefix~=x.prefix then

                A.turnID=A.turnID+1;A.lastSentTurn=nil;A.newTurnAt=os.clock();A.failedThisTurn={};A.failedPrefix=x.prefix;A.awaitingResult=nil;A.fastRetry=false;A.attemptsThisTurn=0

            end

        else

            A.stage='WAITING'

            if previous and previous.ours then A.turnID=A.turnID+1;A.fastRetry=false end

        end

        A.prefix=x.prefix or ''

        if usable and A.enabled and A.attemptsThisTurn<A.maxAttempts and A.lastSentTurn~=A.turnID and not A.inputLock and not A.awaitingResult and os.clock()-(A.newTurnAt or 0)>.07 then

            local word=choose(x.prefix,x.suffix,x.input~='' and x.input or nil)

            if not word and x.input~='' and valid(x.input) and x.input:sub(1,#x.prefix)==x.prefix and not A.bad[x.input] and not A.used[x.input] and not A.failedThisTurn[x.input] then word=x.input end

            if not word then word=choose(x.prefix,x.suffix) end

            A.current=word or ''

            if word and not A.hint then

                local remaining=getTimeLeft()

                local estimate=(#x.input*.035 + #word*((A.fastRetry and A.retrySpeed or A.speed)+.024))+.25

                if remaining and remaining<estimate then

                    setStatus(string.format('Only %.1fs left; skipping risky rewrite',remaining))

                    word=nil

                end

            end

            if word and not A.hint then

                local id=A.turnID;A.lastSentTurn=id;A.inputLock=true

                task.spawn(function()

                    local ok,result=pcall(typeAnswer,word,x.prefix,id)

                    if not ok then result='runtime:'..tostring(result) end

                    A.inputLock=false

                    if result~='cancelled' and not tostring(result):find('^submitted:') then

                        A.failures=A.failures+1;setStatus('Input: '..tostring(result))

                        if id==A.turnID and A.attemptsThisTurn<A.maxAttempts then A.fastRetry=true;A.lastSentTurn=nil;task.wait(.08) end

                    else setStatus(tostring(result)) end

                end)

            elseif not word then setStatus('No unused candidate for '..x.prefix..' (dictionary may still be loading)') end

        elseif not usable then A.current='' end

        -- Five successfully sent submissions maximum per turn; typing failures do not consume an attempt.

        -- A rejected submission often remains visible in the input. Retry without

        -- waiting for a new turn, but only when the SAME complete word remains.

        local pending=A.awaitingResult

        if pending then

            if x.ended or not x.ours or x.prefix~=pending.prefix or A.turnID~=pending.id then

                A.awaitingResult=nil

            elseif os.clock()-pending.at >= A.resultWait then

                if x.input==pending.word then

                    A.fastRetry=true

                    A.failedThisTurn[pending.word]=true

                    A.awaitingResult=nil

                    A.lastSentTurn=nil

                    A.tries=A.tries+1

                    if A.attemptsThisTurn>=A.maxAttempts then

                        setStatus('5/5 submissions used. Waiting for next turn')

                    else

                        setStatus('Possibly rejected: '..pending.word..'; trying a new word')

                    end

                elseif x.input=='' then

                    -- An empty field can mean processing, not necessarily rejection.

                    if os.clock()-pending.at>0.75 then

                        A.awaitingResult=nil

                        -- Cleared field might mean server acceptance. Do NOT spend another attempt.

                        A.lastSentTurn=A.turnID

                        setStatus('Input cleared after Enter; waiting for turn result')

                    end

                elseif x.input~=pending.word then

                    -- Do not punish a partial keyboard render as a rejected word.

                    if os.clock()-pending.at>.65 then

                        A.awaitingResult=nil

                        A.fastRetry=true

                        A.failedThisTurn[pending.word]=true

                        A.lastSentTurn=nil

                        setStatus('Unexpected input change; attempting another word')

                    end

                end

            end

        end

        if os.clock()-lastRefresh>.15 then

            lastRefresh=os.clock()

            stage.Text=A.stage;prefixText.Text=x.prefix and x.prefix:upper() or '---'

            wordText.Text='Suggested: '..(A.current~='' and A.current:upper() or '---')

            statusText.Text=A.status

            switch.Text=A.enabled and 'AUTO: ON' or 'AUTO: OFF'

            local count=0;for _ in pairs(A.used) do count=count+1 end

            local rc=0;for _ in pairs(A.rival) do rc=rc+1 end

            meta.Text=string.format('Words: %d | Used: %d | Rival: %d',D.loaded,count,rc)

            stats.Text=string.format('Input: %s | %s %dms | attempts: %d/%d | errors: %d',A.method~='' and A.method or 'AUTO',A.fastRetry and 'RETRY' or 'NORMAL',math.floor((A.fastRetry and A.retrySpeed or A.speed)*1000+.5),A.attemptsThisTurn,A.maxAttempts,A.failures)

        end

        if os.clock()-lastSave>1.5 then

            lastSave=os.clock()

            if A.usedDirty then saveUsed() end

            if A.knowledgeDirty then saveKnowledge() end

        end

        previous=x

        task.wait(.055)

    end

end



-- Restart the loop on unexpected runtime errors without creating another GUI.

task.spawn(function()

    while A.alive and gui.Parent do

        local ok,err=xpcall(loop,function(e)return tostring(e)end)

        if ok then break end

        A.failures=A.failures+1

        setStatus('Loop error: '..tostring(err):sub(1,125))

        warn('[FTW AutoWord loop]',err)

        task.wait(.65)

    end

end)

print('[FTW AutoWord] Interface initialized')

end



local httpRequest = request or http_request or (syn and syn.request) or (http and http.request)

local deviceFile = 'ftw_autoword_installation_v1.txt'
local keyCacheFile = 'ftw_autoword_key_cache_v1.txt'
local cacheFiles = {keyCacheFile, 'xenox_key_cache_v1.txt'}

local function validKey(value)
    if type(value) ~= 'string' then return nil end
    value = value:match('^%s*(.-)%s*$'):upper()
    local suffix = value:match('^FTW%-(%x+)$') or value:match('^XENO%-(%x+)$')
    return (suffix and #suffix == 64) and value or nil
end

local function cacheKey(key)
    if type(writefile) == 'function' then pcall(writefile, keyCacheFile, key) end
end

local function readCachedKey()
    if type(readfile) ~= 'function' then return nil end
    for _, file in ipairs(cacheFiles) do
        local ok, value = pcall(readfile, file)
        local key = ok and validKey(value)
        if key then return key end
    end
    return nil
end

local function clearCachedKey()
    for _, file in ipairs(cacheFiles) do
        local removed = false
        if type(delfile) == 'function' then removed = pcall(delfile, file) end
        if not removed and type(writefile) == 'function' then pcall(writefile, file, '') end
    end
end

local deviceToken = env.FTW_AUTOWORD_DEVICE_TOKEN or env.XENO_DEVICE_TOKEN

if type(readfile) == 'function' then

    for _, file in ipairs({deviceFile, 'xenox_installation_v1.txt'}) do
        local ok, saved = pcall(readfile, file)
        if ok and type(saved) == 'string' and #saved == 64 and saved:match('^[a-f0-9]+$') then deviceToken = saved; break end
    end

end

if type(deviceToken) ~= 'string' or #deviceToken ~= 64 or not deviceToken:match('^[a-f0-9]+$') then

    deviceToken = (Http:GenerateGUID(false) .. Http:GenerateGUID(false)):gsub('-', ''):lower()

end

env.FTW_AUTOWORD_DEVICE_TOKEN = deviceToken

if type(writefile) == 'function' then pcall(writefile, deviceFile, deviceToken) end



local alive, busy, generation = true, false, 0

local activeKey, deadline, running = nil, 0, false

local gui = Instance.new('ScreenGui')

gui.Name = 'FTW_AutoWord_KeySystem'

gui.ResetOnSpawn = false

gui.DisplayOrder = 1000

gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

gui.Parent = player:WaitForChild('PlayerGui')

local panel = Instance.new('Frame')

panel.Size = UDim2.new(0.9, 0, 0, 350)

panel.AnchorPoint = Vector2.new(0.5, 0.5)

panel.Position = UDim2.fromScale(0.5, 0.5)

panel.BackgroundColor3 = Color3.fromRGB(18, 21, 30)

panel.BorderSizePixel = 0

panel.Parent = gui

local constraint = Instance.new('UISizeConstraint', panel)

constraint.MaxSize = Vector2.new(460, 350)

Instance.new('UICorner', panel).CornerRadius = UDim.new(0, 14)

local function text(class, content, y, height)

    local item = Instance.new(class)

    item.Size = UDim2.new(1, -40, 0, height)

    item.Position = UDim2.new(0, 20, 0, y)

    item.BackgroundColor3 = Color3.fromRGB(31, 37, 52)

    item.BorderSizePixel = 0

    item.Font = Enum.Font.Gotham

    item.TextSize = 15

    item.TextColor3 = Color3.fromRGB(235, 239, 250)

    item.Text = content

    item.Parent = panel

    Instance.new('UICorner', item).CornerRadius = UDim.new(0, 8)

    if class == 'TextLabel' then item.BackgroundTransparency = 1; item.TextWrapped = true end

    return item

end

local title = text('TextLabel', 'FTW AutoWord | Access key', 14, 35)

title.Font = Enum.Font.GothamBold; title.TextSize = 22

text('TextLabel', 'Complete the Linkvertise steps for 24-hour access.', 52, 40)

local input = text('TextBox', '', 103, 42)

input.PlaceholderText = 'Enter key'

input.ClearTextOnFocus = false

input.TextSize = 13

local verify = text('TextButton', 'Verify key', 155, 40)

verify.BackgroundColor3 = Color3.fromRGB(88, 75, 224)

local get = text('TextButton', 'Get key', 205, 40)

local status = text('TextLabel', 'A key is required to start.', 255, 45)

status.TextSize = 13

local close = text('TextButton', 'Close', 308, 27)

local link = text('TextBox', '', 255, 45)

link.TextSize = 12; link.ClearTextOnFocus = false; link.Visible = false



local function stopScript()

    running = false; activeKey = nil; generation = generation + 1

    if type(env.FTW41_STOP) == 'function' then pcall(env.FTW41_STOP) end

end

local function cleanup()

    if not alive then return end

    alive = false; stopScript(); gui:Destroy()

end

env.FTW_AUTOWORD_KEY_STOP = cleanup

close.Activated:Connect(cleanup)

local function show(message)

    if not alive then return end

    gui.Enabled = true; link.Visible = false; status.Visible = true; status.Text = message

end

local function api(path, key)

    if type(httpRequest) ~= 'function' then return nil, 'This executor does not support HTTP requests.' end

    if KEY_API:find('YOUR%-SUBDOMAIN') or KEY_API:sub(1, 8) ~= 'https://' then return nil, 'The owner must configure the key server URL.' end

    local done, response, success = false, nil, false

    task.spawn(function()

        success, response = pcall(httpRequest, {

            Url = KEY_API .. path, Method = 'POST', Timeout = 15,

            Headers = {['Content-Type'] = 'application/json'},

            Body = Http:JSONEncode({userId = tostring(player.UserId), deviceToken = deviceToken, key = key})

        })

        done = true

    end)

    local untilTime = os.clock() + 20

    repeat task.wait(0.05) until done or not alive or os.clock() >= untilTime

    if not alive or not done or not success or type(response) ~= 'table' then return nil, 'Cannot reach the key server. Try again.' end

    local ok, data = pcall(function() return Http:JSONDecode(response.Body) end)

    if not ok or type(data) ~= 'table' then return nil, 'Invalid server response.' end

    local code = tonumber(response.StatusCode) or 0

    if code < 200 or code >= 300 then return nil, data.error or 'Invalid or expired key for this installation.', code end

    return data

end

get.Activated:Connect(function()

    if busy or not alive then return end

    busy = true; show('Creating your Linkvertise link...')

    local data, err = api('/api/start')

    if alive then

        if data and type(data.url) == 'string' and data.url:sub(1, #KEY_API + 9) == KEY_API .. '/start?t=' then

            local copied = false

            if type(setclipboard) == 'function' then copied = pcall(setclipboard, data.url) end

            show(copied and 'Link copied. Open it in your browser, finish the steps, then enter your key.' or 'Copy the link below and open it in your browser.')

            if not copied then status.Visible = false; link.Text = data.url; link.Visible = true; link:CaptureFocus() end

        else show(err or 'Could not create a key link.') end

    end

    busy = false

end)

local function authorize(key, automatic)
    if busy or not alive then return end
    key = validKey(key)
    if not key then
        if not automatic then show('Enter a valid FTW- key.') end
        return
    end

    busy = true
    show(automatic and 'Checking saved key...' or 'Verifying key...')
    local began = os.clock()
    local data, err, statusCode = api('/api/verify', key)
    if alive then
        if data and data.valid == true and type(data.expiresIn) == 'number'
            and data.expiresIn > os.clock() - began then
            activeKey = key
            deadline = began + math.min(data.expiresIn, 86400)
            cacheKey(key)
            generation = generation + 1
            gui.Enabled = false
            local ok, launchErr = pcall(launchAutoWord)
            running = ok
            if not ok then
                stopScript()
                show('FTW AutoWord failed to start: '..tostring(launchErr):sub(1, 120))
            end
        else
            -- A server-confirmed invalid/expired key must not be reused.
            -- Connection failures leave the saved key for a later retry.
            if data or statusCode == 403 then
                clearCachedKey()
            end
            show(err or 'The key has expired. Get a new key.')
        end
    end
    busy = false
end

verify.Activated:Connect(function()
    authorize(input.Text, false)
end)

task.spawn(function()
    local saved = readCachedKey()
    if saved and alive then
        input.Text = saved
        authorize(saved, true)
    end
end)

task.spawn(function()

    local nextCheck = 0

    while alive do

        if running and os.clock() >= deadline then

            clearCachedKey(); stopScript(); show('Your key has expired. Get a new key to continue.')

        elseif running and os.clock() >= nextCheck then

            nextCheck = os.clock() + 60

            local version, began = generation, os.clock()

            local data, err, statusCode = api('/api/verify', activeKey)

            if alive and running and generation == version then

                if not data or data.valid ~= true or type(data.expiresIn) ~= 'number' or data.expiresIn <= os.clock() - began then

                    if data or statusCode == 403 then clearCachedKey() end; stopScript(); show(err or 'Access expired. Verify a new key to continue.')

                else deadline = began + math.min(data.expiresIn, 86400) end

            end

        end

        task.wait(0.5)

    end

end)

-- A separate expiry timer stops the script even while a network call is pending.

task.spawn(function()

    while alive do

        if running and os.clock() >= deadline then clearCachedKey(); stopScript(); show('Your key has expired. Get a new key to continue.') end

        task.wait(0.25)

    end

end)
