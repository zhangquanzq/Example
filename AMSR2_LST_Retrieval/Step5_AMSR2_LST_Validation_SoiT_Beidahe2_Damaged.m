%% 使用北大河流域站点观测的温度数据验证AMSR2地表温度.
% 此程序将同一站点的昼夜数据放到同一幅散点图上.

%% 功能标记和预设参数.
% 指定站点片区的标记. 1表示玉门东, 2表示吊达坂沟, 3表示七一冰川.
flg1 = 1;

% 站点片区名称.
siteGroup = {'Yumendong', 'Diaodabangou', 'QiyiGlacier'};
siteGroup = siteGroup{flg1};

% 昼夜, 过境时间.
daynightTypes = {'Day', 'Night'};
daynightTypesN = length(daynightTypes);
transitTypes = {'1330', '0130'};

%% 路径.
% 根目录.
rootDir = 'I:\AMSR2_MODIS_AW_LST';
addpath(fullfile(rootDir, 'Code/Functions/'))
retrievalDir = fullfile(rootDir, 'AMSR2_LST_Retrieval');
dataPath = fullfile(retrievalDir, 'Data');
figPath = fullfile(retrievalDir, 'Figures');

% 输入数据路径.
featureDir = fullfile(dataPath, 'Feature');
siteTrDir = fullfile(dataPath, 'SiteData\Beidahe\SoilTRecords');
amsr2LstDir = fullfile(dataPath, 'AMSR2_4_LSTCN_TIF');
modisUpscaleDir = fullfile(dataPath, 'MYD11A1_3_UpscalingCn_TIF');

% 输出数据路径.
siteMatDir = fullfile(dataPath, 'SiteSoilT_Matlab');
if ~exist(siteMatDir, 'dir')
    mkdir(siteMatDir)
end
siteFigureDir = fullfile(figPath, 'SiteSoilT_DaynightCombine');
if ~exist(siteFigureDir, 'dir')
    mkdir(siteFigureDir)
end

%% 整理站点片区的土壤温度观测数据, 并保存为Mat文件.
% 获取站点属性信息.
siteStruct = shaperead(fullfile(featureDir, 'Sites_Location_Beidahe.shp'));
siteLocationList = [[siteStruct.X]; [siteStruct.Y]]';
siteNameList = {siteStruct.Name}';

% 获取片区站点文件名称列表.
siteTrXlsxList = dir(fullfile(siteTrDir, '*.xlsx'));
siteTrXlsxList = {siteTrXlsxList.name}';
siteTrXlsxList = siteTrXlsxList(contains(siteTrXlsxList, siteGroup));
siteTrXlsxN = length(siteTrXlsxList);

% 分昼夜获取MODIS过境时刻的站点观测温度, 并存储为Mat文件.
for i = 1: daynightTypesN
    daynight = daynightTypes{i};

    % 判断Mat文件是否存在.
    siteMatPath = fullfile(siteMatDir, sprintf('SiteSoilT_%s_%s.mat', siteGroup, daynight));
    if exist(siteMatPath, 'file')
        continue
    end

    % 创建存储数据的表, 表包括4个字段, 分别是: 站点名, 站点位置, 时间列表, 温度列表.
    siteDataCell = cell(siteTrXlsxN, 4);
    for j = 1: siteTrXlsxN
        % 获取站点的观测时刻与温度记录.
        siteTrXlsx = siteTrXlsxList{j};
        siteTrTable = readtable(fullfile(siteTrDir, siteTrXlsx));
        siteDatetimeRecords = siteTrTable.Time;
        siteSoilTRecords = siteTrTable.T_C;

        % 获取有站点观测的日期的MODIS过境时刻列表.
        siteDateRecords = datetime(string(siteDatetimeRecords, 'yyyMMdd'), InputFormat='yyyyMMdd');
        modisDatetimeList = strcat(string(unique(siteDateRecords), 'yyyyMMdd'), transitTypes{i});
        modisDatetimeList = datetime(modisDatetimeList, InputFormat='yyyyMMddHHmm');

        % 获取与MODIS过境时刻最近的站点观测时间和温度列表.
        modisDatetimeN = length(modisDatetimeList);
        siteDatetimeList = strings(modisDatetimeN, 1);
        siteSoilTList = zeros(modisDatetimeN, 1) * nan;
        siteModisDurationIndex = true(modisDatetimeN, 1);
        for k = 1: modisDatetimeN
            datetimeDiff = abs(siteDatetimeRecords - modisDatetimeList(k));
            if min(datetimeDiff) > minutes(2.5)
                siteModisDurationIndex(k) = false;
                continue
            end
            datetimeDiffMinIndex = find(datetimeDiff == min(datetimeDiff), 1);
            siteDatetimeList(k) = siteDatetimeRecords(datetimeDiffMinIndex);
            siteSoilTList(k) = siteSoilTRecords(datetimeDiffMinIndex);
        end
        modisDatetimeList = modisDatetimeList(siteModisDurationIndex);
        siteDatetimeList = siteDatetimeList(siteModisDurationIndex);
        siteDatetimeList = datetime(siteDatetimeList, InputFormat='yyyy-MM-dd HH:mm:ss');
        siteSoilTList = siteSoilTList(siteModisDurationIndex);

        % 插值MODIS过境时刻的站点温度.
        siteModisSoilTList = interp1(siteDatetimeRecords, siteSoilTRecords, modisDatetimeList, ...
            'spline');

        % 整理站点观测数据.
        [~, siteName] = fileparts(siteTrXlsx);
        fprintf('整理站点%s %s的观测数据.\n', siteName, daynight)
        siteDataCell{j, 1} = siteName;
        for k = 1: length(siteNameList)
            if contains(siteName, siteNameList{k})
                siteDataCell{j, 2} = siteLocationList(k, :);
                break
            end
        end
        siteDataCell{j, 3} = modisDatetimeList;
        siteDataCell{j, 4} = siteModisSoilTList;
    end

    % 输出站点观测记录表到Mat文件.
    tableVarStr = sprintf('site%sDataTable', daynight);
    siteDataTable = cell2table(siteDataCell, ...
        VariableNames=["SiteName" "Location" "Datetime" "SoilTemperature"]);
    assignin('base', tableVarStr, siteDataTable)
    save(siteMatPath, tableVarStr)
end

%% 校正站点观测数据, 并验证反演的AMSR2温度.
% 获取AMSR2 LST影像每个像元的经纬度坐标矩阵, 升尺度后的MODIS LST与AMSR2 LST的信息一样.
amsr2LstPath = fullfile(amsr2LstDir, 'AMSR2_LST_2012XXXX_TIF', 'AMSR2_LST_Day_20120703.tif');
amsr2Ref = geotiffinfo(amsr2LstPath).SpatialRef;
lonMin = amsr2Ref.LongitudeLimits(1);
lonMax = amsr2Ref.LongitudeLimits(2);
latMin = amsr2Ref.LatitudeLimits(1);
latMax = amsr2Ref.LatitudeLimits(2);
cellsizeX = amsr2Ref.CellExtentInLongitude;
cellsizeY = amsr2Ref.CellExtentInLatitude;
lonVector = lonMin + cellsizeX/2: cellsizeX: lonMax - cellsizeX/2;
latVector = latMax - cellsizeY/2: -cellsizeY: latMin + cellsizeY/2;

% 获取站点片区内各站点的名称, 位置, 以及昼夜的时间, 温度数据列表.
siteDayMatPath = fullfile(siteMatDir, sprintf('SiteSoilT_%s_Day.mat', siteGroup));
load(siteDayMatPath, 'siteDayDataTable');
siteNameList = siteDayDataTable.SiteName;
siteLocationList = siteDayDataTable.Location;

[siteDatetimeCell, siteSoilTCell] = deal(cell(daynightTypesN, 1));
for i = 1: daynightTypesN
    daynight = daynightTypes{i};
    siteMatPath = fullfile(siteMatDir, sprintf('SiteSoilT_%s_%s.mat', siteGroup, daynight));
    siteVarStr = sprintf('site%sDataTable', daynight);
    load(siteMatPath, siteVarStr); siteDataTable = eval(siteVarStr);
    siteDatetimeCell{i} = siteDataTable.Datetime;
    siteSoilTCell{i} = siteDataTable.SoilTemperature;
end

% 按站点验证AMSR2 LST.
for i = 1: length(siteNameList)
    % 站点名称, 位置.
    siteName = siteNameList{i}; siteName2 = replace(siteName, '_', ' ');
    siteLocation = siteLocationList(i, :);

    % 获取站点位置在AMSR2 LST数据上的行列号.
    lonDiffVector = abs(lonVector - siteLocation(1));
    latDiffVector = abs(latVector - siteLocation(2));
    lstCol = find(lonDiffVector == min(lonDiffVector), 1);
    lstRow = find(latDiffVector == min(latDiffVector), 1);

    % 分年度验证AMSR2 LST.
    siteYearTypes = unique(siteDatetimeCell{1}{i}.Year);
    for j = 1: length(siteYearTypes)
        siteYear = siteYearTypes(j);

        % 判断是否有站点观测年份的AMSR2 LST.
        amsr2LstYearDir = fullfile(amsr2LstDir, sprintf('AMSR2_LST_%dXXXX_TIF', siteYear));
        if ~exist(amsr2LstYearDir, 'dir')
            continue
        end

        % 获取校正站点温度的系数, 站点观测温度, 以及MODIS LST.
        modisLstYearDir = fullfile(modisUpscaleDir, sprintf('MYD11A1_%dXXX_TIF', siteYear));
        [pCell, siteSoilTInYearCell, modisLstCell] = deal(cell(daynightTypesN, 1));
        for k = 1: daynightTypesN
            % 获取当前年份站点观测日期列表.
            siteDatetimeList = siteDatetimeCell{k}{i};
            siteYearIndex = (siteDatetimeList.Year == siteYear);
            siteDateInYearList = string(siteDatetimeList(siteYearIndex), 'yyyyMMdd');

            % 获取当前年份升尺度后MODIS LST的日期列表.
            modisLstName = sprintf('MYD11A1*_%s.tif', daynII*     �             ^      �                                      =       B    �   C    �   D    �   E    �   S       ��    �       �  �  �  \   �    �   �  &
  �
���������������o��H6��ȿ*�A
Wȁ���uP|Pp-��=�&��{��w���ٵ�wlO�:�|>��.]�1�:ך��K	����*���������7���?2~]� /�U|�5�[��h��ٕ����7��=���G��0�;���Y�k���#T|5�0�zx
���:�A�./o�ў��R�<���r�����~7��x4���I��� ��?A��,�t��W�����T��ގ�q��?�#lGLE����v�`He�|��=g����� _R]�\��;V:9߅�u�w�7cN��|u�
��q
���LJ��{��7������6���
D�A���з�X���~C�|��CHo�͔�ן ��˲���������v���𥃼V[� m��W���I���<O��<�{>:�҉�4|!��A�_�e���|q4?E�/@Kx����r�:�
ꤋ�q<�����tbx
|��G|L8�.wL���������$'`�B����$�܊�}��~��3�+c
-8��IUn��οK���n���>b/�|5ự/��8�///����}�Z�p��ֱ��-�������^r���-�o���($��R��cCoo��������[,^<�6������E�+\��`���`��G�׼��
���A,���
��W��y��'O������ǎ�z�>�[<��������x�����0����@��ܕ�Wv^؉�tԉԮ�e��vB�m9ǯǑ�������[+�+e}l�	"C���;��__׶m��������_�����C+�@�<7 �,==r��������������7�����uU������iv �خ ھ�>�����
���;�p�; -D�oL��'7"�G�]'�1r�#��i�IgMB��<V/�?�Oi�~U���?7ชQ�~!��p��5��W���f�\D���^�3����3w���a��}�[��[4�����cϿ;��w]ce���z`�?��\0|�}���v�����x����ǿm@��O��F�A��X�R��
���1�b���d��z���O����+O��9\v7���~I��4��<�~@Z'֟�D�?�����|�����#ϗO���W���Se���������~D�����S�X���' �������_c��C�������8��5�[���0}A�� S��	�0Lj��#�����P(�x����
�q��-�/�U��׀�}     ��       ���}�3�x���n�0F�+�@���y;?��v�2�Pw}F��z>;N��I����m�������X�ȴN�3��\北���7���E�\_��	��8@������e��-�/��8�I����-��]����x��/Y��~9S'�&�`G��n����ߦ~D*���.&wҀ=A3˔�ﮦf�!-}�]���ҏ� 8���6�c�E�R�w��r$;��!w���ig��}�rT�a���;o߆����qL��g/�㉝���#���R�~��)�����':����`��,�?������p�Ư���[��o��K�^ȗ��/o��k}O�&��_xf��]|A�^yQ~�?�>�
 �O���?^:��b����.��u~ğ&:�վr������\����o9v�0���� ���/�8@+�=� ?07�k����G�Q�=�/]!���w5�Z�i ^0�l�����)����W�0���  O��J����s�3����� ��l�r .؍����	����)�l���z�n�����
�WJ/����v.�RӋ��w�v�8^�<����x����e����������x3z=��~G wiB:J³N���i�>n��<k���P����y�=�w�����?�Ǉ����n�+���KQEQEQEQEQEQEQEQ��w��#x���� =	��Χwhmz(8�0mw�xa��($�;iM)�3s	�G�K�@(��o(�=���7��eW�gُzYz�u|��ze���c�_�2~����&��	�O���?��~̯�?�7���A�A�\?V٭�E��V�㲜C��ė��f���{�o�����R��o���VH�=�zA��7��/֟�?����.՟��l���+�O�����88���?���?��               ���a�}�                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        iteDateInYearList);

            % 获取共同日期的站点温度列表, 并校正.
            siteAllSoilTMeanList = siteAllSoilTMeanCell{k};
            siteSoilTInYearList = siteAllSoilTMeanList(siteYearIndex);
            siteSoilTInYearList = siteSoilTInYearList(siteDateIndex) + 273.15;
            siteLstInYearList = polyval(pCell{k}, siteSoilTInYearList);

            % 获取共同日期AMSR2 LST影像中站点所在像元的温度列表.
            amsr2LstNameList = amsr2LstNameList(amsr2DateIndex);
            amsr2LstNameN = length(amsr2LstNameList);
            amsr2LstList = zeros(amsr2LstNameN, 1)