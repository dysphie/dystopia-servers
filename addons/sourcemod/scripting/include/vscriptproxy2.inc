enum VScriptCallType
{
	VScriptCall_Static,
	VScriptCall_Entity,
	VScriptCall_Player
}

enum VScriptType
{
	VScriptType_Entity,
	VScriptType_Player,
	VScriptType_Vector,
	VScriptType_Float,
	VScriptType_Int,
	VScriptType_Bool
}

methodmap VScriptCall < Handle
{
	public native VScriptCall(VScriptCallType type, const char[] fnName);

	public native void Call(any ...);

	public native void AddParam(VScriptType type);
}