﻿using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
namespace MPipeline
{
    [CreateAssetMenu(menuName = "GPURP Events/Property Set")]
    public class PropertySetEvent : PipelineEvent
    {
        public Matrix4x4 lastViewProjection { get; private set; }
        public Matrix4x4 nonJitterVP { get; private set; }
        public Matrix4x4 inverseNonJitterVP { get; private set; }
        private System.Func<PipelineCamera, LastVPData> getLastVP = (c) => new LastVPData(GL.GetGPUProjectionMatrix(c.cam.projectionMatrix, false) * c.cam.worldToCameraMatrix);
        public override void FrameUpdate(PipelineCamera cam, ref PipelineCommandData data)
        {
            LastVPData lastData = IPerCameraData.GetProperty(cam, getLastVP);
            //Calculate Last VP for motion vector and Temporal AA
            nonJitterVP = GL.GetGPUProjectionMatrix(cam.cam.nonJitteredProjectionMatrix, false) * cam.cam.worldToCameraMatrix;
            ref Matrix4x4 lastVp = ref lastData.lastVP;
            lastViewProjection = lastVp;
            CommandBuffer buffer = data.buffer;
            buffer.SetGlobalMatrix(ShaderIDs._LastVp, lastVp);
            buffer.SetGlobalMatrix(ShaderIDs._NonJitterVP, nonJitterVP);
            inverseNonJitterVP = nonJitterVP.inverse;
            buffer.SetGlobalMatrix(ShaderIDs._InvNonJitterVP, inverseNonJitterVP);
            buffer.SetGlobalMatrix(ShaderIDs._InvVP, data.inverseVP);
            buffer.SetGlobalMatrix(ShaderIDs._VP, data.vp);
            buffer.SetGlobalMatrix(ShaderIDs._InvLastVP, lastVp.inverse);
            lastVp = nonJitterVP;
            
        }
        protected override void Init(PipelineResources resources)
        {

        }
        protected override void Dispose()
        {
        }
        public override bool CheckProperty()
        {
            return true;
        }
    }

    public class LastVPData : IPerCameraData
    {
        public Matrix4x4 lastVP = Matrix4x4.identity;
        public LastVPData(Matrix4x4 lastVP)
        {
            this.lastVP = lastVP;
        }
        public override void DisposeProperty()
        {
        }
    }
}