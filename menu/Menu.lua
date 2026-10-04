--[[
	Menu.lua
		Functions for the Bagnon right click options menu
--]]

--show the menu
function BagnonMenu_Show(frame)
	BagnonMenu.frame = frame;
	
	BagnonMenu.onShow = 1;
	BagnonMenuText:SetText(frame:GetName() .. " Settings");
	
	--Set values
	BagnonMenuLocked:SetChecked(BagnonSets[frame:GetName()].locked);
	BagnonMenuStayOnScreen:SetChecked(BagnonSets[frame:GetName()].stayOnScreen);
	local bgSets = BagnonSets[frame:GetName()].bg;
	BagnonMenuBGSettingsNormalTexture:SetVertexColor(bgSets.r, bgSets.g, bgSets.b, bgSets.a);
	local bc = BagnonSets[frame:GetName()].border or {r = 1, g = 1, b = 1};
	BagnonMenuBorderSettingsNormalTexture:SetVertexColor(bc.r, bc.g, bc.b);
	
	BagnonMenuReverse:SetChecked(BagnonSets[frame:GetName()].reverse);
	BagnonMenuColumns:SetValue(frame.cols);
	BagnonMenuSpacing:SetValue(frame.space);
	BagnonMenuScale:SetValue(frame:GetScale() * 100);
	BagnonMenuOpacity:SetValue(frame:GetAlpha() * 100);
	
	if(BagnonSets[frame:GetName()].strata) then
		BagnonMenuStrata:SetValue(BagnonSets[frame:GetName()].strata);
	else
		BagnonMenuStrata:SetValue(3);
	end
	
	--a nifty thing I saw in meta map adapted for my usage
	--places the options menu at the cursor's position
	local x, y = GetCursorPosition();
	x = x / UIParent:GetScale();
	y = y / UIParent:GetScale();
	
	BagnonMenu:ClearAllPoints();
	BagnonMenu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x - 32, y + 48);
	
	BagnonMenu:Show();
	BagnonMenu.onShow = nil;
end

--change <frame>'s transparency
function BagnonMenu_SetAlpha(frame, alpha)
	if(alpha ~= 1) then
		BagnonSets[frame:GetName()].alpha = alpha;
	else
		BagnonSets[frame:GetName()].alpha = nil
	end
	frame:SetAlpha(alpha);
end

--Set and scale <frame>
function BagnonMenu_SetScale(frame, scale)
	BagnonSets[frame:GetName()].scale = scale;
	
	Infield.Scale(frame, scale);
	BagnonFrame_SavePosition(frame);
end

--set the background of the frame between opaque/transparent
function BagnonMenuBG_OnClick(frame)
	if(ColorPickerFrame:IsShown()) then
		ColorPickerFrame:Hide();
	else
		local bgSets = BagnonSets[frame:GetName()].bg;
		
		ColorPickerFrame.frame = frame;
		ColorPickerFrame.func = BagnonMenuBG_ColorChange;
		
		ColorPickerFrame.hasOpacity = 1;
		ColorPickerFrame.opacityFunc = BagnonMenuBG_AlphaChange;
		ColorPickerFrame.cancelFunc = BagnonMenuBG_CancelChanges;
		
		BagnonMenuBGSettingsNormalTexture:SetVertexColor(bgSets.r, bgSets.g, bgSets.b, bgSets.a);
		ColorPickerFrame:SetColorRGB(bgSets.r, bgSets.g, bgSets.b);
		ColorPickerFrame.opacity = 1 - bgSets.a;
		ColorPickerFrame.previousValues = {r = bgSets.r, g = bgSets.g, b = bgSets.b, opacity = bgSets.a};
		
		ShowUIPanel(ColorPickerFrame);
	end
end

function BagnonMenuBG_ColorChange()
	local r, g, b = ColorPickerFrame:GetColorRGB();
	local frame = ColorPickerFrame.frame;
	local a = BagnonSets[frame:GetName()].bg.a;
	
	frame:SetBackdropColor(r, g, b, a);
	BagnonFrame_ApplyBorder(frame, a);
	BagnonMenuBGSettingsNormalTexture:SetVertexColor(r, g, b, a);
	
	BagnonSets[frame:GetName()].bg.r = r;
	BagnonSets[frame:GetName()].bg.g = g;
	BagnonSets[frame:GetName()].bg.b = b;
end

function BagnonMenuBG_AlphaChange()
	local frame = ColorPickerFrame.frame;
	local bgSets = BagnonSets[frame:GetName()].bg;
	local alpha = 1 - OpacitySliderFrame:GetValue();

	frame:SetBackdropColor(bgSets.r, bgSets.g, bgSets.b, alpha);
	BagnonFrame_ApplyBorder(frame, alpha);
	BagnonMenuBGSettingsNormalTexture:SetVertexColor(bgSets.r, bgSets.g, bgSets.b, alpha);
	
	BagnonSets[frame:GetName()].bg.a = alpha;
end

function BagnonMenuBG_CancelChanges() 
	local prevValues = ColorPickerFrame.previousValues;
	local frame = ColorPickerFrame.frame;
	
	frame:SetBackdropColor(prevValues.r, prevValues.g, prevValues.b, prevValues.opacity);
	BagnonFrame_ApplyBorder(frame, prevValues.opacity);
	
	BagnonMenuBGSettingsNormalTexture:SetVertexColor(prevValues.r, prevValues.g, prevValues.b, prevValues.opacity);
	BagnonSets[frame:GetName()].bg.r = prevValues.r;
	BagnonSets[frame:GetName()].bg.g = prevValues.g;
	BagnonSets[frame:GetName()].bg.b = prevValues.b;
	BagnonSets[frame:GetName()].bg.a = prevValues.opacity;
end

--set the inventory slots to be organized in either a reversed or normal order
function BagnonMenu_ToggleOrder(frame, checked)
	if( checked ) then
		BagnonSets[frame:GetName()].reverse = 1;
	else
		BagnonSets[frame:GetName()].reverse = nil;
	end
	BagnonFrame_OrderBags(frame, checked);
	BagnonFrame_Generate(frame);
end

function BagnonMenu_ToggleLock(frame, checked)
	local frameName = frame:GetName();
	
	if(checked) then
		BagnonSets[frameName].locked = 1;
	else
		BagnonSets[frameName].locked = nil;
	end
end

function BagnonMenu_ToggleStayOnScreen(frame, checked)
	local frameName = frame:GetName();
	
	if(checked) then
		BagnonSets[frameName].stayOnScreen = 1;
		frame:SetClampedToScreen(true);
	else
		BagnonSets[frameName].stayOnScreen = nil;
		frame:SetClampedToScreen(false);
	end
end


--[[ Border color ]]--

function BagnonMenuBorder_OnClick(frame)
	if(ColorPickerFrame:IsShown()) then
		ColorPickerFrame:Hide();
	else
		local bc = BagnonSets[frame:GetName()].border or {r = 1, g = 1, b = 1};

		ColorPickerFrame.frame = frame;
		ColorPickerFrame.func = BagnonMenuBorder_ColorChange;
		ColorPickerFrame.hasOpacity = nil;
		ColorPickerFrame.opacityFunc = nil;
		ColorPickerFrame.cancelFunc = BagnonMenuBorder_CancelChanges;

		ColorPickerFrame:SetColorRGB(bc.r, bc.g, bc.b);
		ColorPickerFrame.previousValues = {r = bc.r, g = bc.g, b = bc.b};

		ShowUIPanel(ColorPickerFrame);
	end
end

function BagnonMenuBorder_ColorChange()
	local r, g, b = ColorPickerFrame:GetColorRGB();
	local frame = ColorPickerFrame.frame;

	BagnonSets[frame:GetName()].border = {r = r, g = g, b = b};
	BagnonFrame_ApplyBorder(frame, BagnonSets[frame:GetName()].bg.a);
	BagnonMenuBorderSettingsNormalTexture:SetVertexColor(r, g, b);
end

function BagnonMenuBorder_CancelChanges()
	local prev = ColorPickerFrame.previousValues;
	local frame = ColorPickerFrame.frame;

	BagnonSets[frame:GetName()].border = {r = prev.r, g = prev.g, b = prev.b};
	BagnonFrame_ApplyBorder(frame, BagnonSets[frame:GetName()].bg.a);
	BagnonMenuBorderSettingsNormalTexture:SetVertexColor(prev.r, prev.g, prev.b);
end

--right click on the swatch: back to the default (white) border
function BagnonMenuBorder_Reset(frame)
	if(ColorPickerFrame:IsShown()) then
		ColorPickerFrame:Hide();
	end

	BagnonSets[frame:GetName()].border = nil;
	BagnonFrame_ApplyBorder(frame, BagnonSets[frame:GetName()].bg.a);
	BagnonMenuBorderSettingsNormalTexture:SetVertexColor(1, 1, 1);
end
