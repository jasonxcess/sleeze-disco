"""Use a Mixamo (mixamorig:*) skinless FBX as the motion SOURCE for retarget.Retarget."""
import retarget as R
def mixamo_roles(prefix='mixamorig:'):
    p=lambda n: prefix+n
    roles={'spineA':(p('Spine'),p('Spine2')),'chest':(p('Spine2'),p('Neck')),'neck':(p('Neck'),p('Head'))}
    for S,s in [('L','Left'),('R','Right')]:
        roles.update({f'{S}clav':(p(s+'Shoulder'),p(s+'Arm')),f'{S}upper':(p(s+'Arm'),p(s+'ForeArm')),f'{S}fore':(p(s+'ForeArm'),p(s+'Hand')),
          f'{S}hand':(p(s+'Hand'),p(s+'HandMiddle1')),f'{S}thigh':(p(s+'UpLeg'),p(s+'Leg')),f'{S}calf':(p(s+'Leg'),p(s+'Foot')),f'{S}foot':(p(s+'Foot'),p(s+'ToeBase'))})
    hip=(p('Hips'),p('LeftUpLeg'),p('RightUpLeg'),p('Spine2'))
    feet=(p('LeftFoot'),p('RightFoot'))
    return roles,hip,feet
